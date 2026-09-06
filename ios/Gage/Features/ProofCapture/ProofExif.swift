import Foundation
import ImageIO

/// Métadonnées de prise de vue jointes à une preuve.
///
/// Deux règles gouvernent ce type.
///
/// **Liste blanche, jamais l'EXIF brut.** Une photo prise par un iPhone porte
/// les coordonnées GPS du lieu où elle a été prise. Nous n'en avons pas besoin
/// pour vérifier une promesse, et les collecter serait contraire à la
/// minimisation exigée par le RGPD. On n'envoie que ce que l'anti-triche lit.
///
/// **Date normalisée en UTC.** L'EXIF stocke `DateTimeOriginal` en heure
/// locale, sans fuseau. Or `parseExifDate` dans `anticheat.ts` l'interprète
/// comme de l'UTC : en France, l'écart de une à deux heures dépasserait la
/// tolérance de cinq minutes et lèverait `exif_date_mismatch` sur chaque
/// preuve honnête. La conversion se fait donc ici, où le décalage est connu.
struct ProofExif: Codable, Equatable, Sendable {
    /// « 2026:09:06 14:32:05 », en UTC.
    let dateTimeOriginal: String?
    /// Logiciel déclaré. L'anti-triche s'attend à y lire Apple.
    let software: String?
    let make: String?
    let model: String?
    let lensModel: String?
    /// Dimensions, utiles pour repérer une image recadrée ou rééchantillonnée.
    let pixelWidth: Int?
    let pixelHeight: Int?

    enum CodingKeys: String, CodingKey {
        case dateTimeOriginal = "DateTimeOriginal"
        case software = "Software"
        case make = "Make"
        case model = "Model"
        case lensModel = "LensModel"
        case pixelWidth = "PixelWidth"
        case pixelHeight = "PixelHeight"
    }

    /// Y a-t-il quelque chose à envoyer ?
    ///
    /// Un objet entièrement vide vaudrait `exif_missing` côté serveur ; autant
    /// n'envoyer rien du tout et laisser le champ nul, ce qui dit la même
    /// chose sans faire croire à une extraction réussie.
    var isEmpty: Bool {
        dateTimeOriginal == nil && software == nil && make == nil
            && model == nil && lensModel == nil
    }
}

extension ProofExif {

    /// Format attendu par `parseExifDate` côté serveur.
    static let dateFormat = "yyyy:MM:dd HH:mm:ss"

    /// Assemble les métadonnées à partir de valeurs déjà lues.
    ///
    /// Séparée de ImageIO à dessein : c'est la partie qui contient la
    /// conversion de fuseau, et elle doit être testable sans image.
    ///
    /// - Parameters:
    ///   - localDate: `DateTimeOriginal` tel qu'écrit dans le fichier.
    ///   - offsetSeconds: décalage du fuseau de prise de vue, tiré de
    ///     `OffsetTimeOriginal` quand il existe, du fuseau de l'appareil sinon.
    static func make(
        localDate: String?,
        offsetSeconds: Int,
        software: String?,
        make maker: String?,
        model: String?,
        lensModel: String?,
        pixelWidth: Int?,
        pixelHeight: Int?
    ) -> ProofExif {
        ProofExif(
            dateTimeOriginal: localDate.flatMap { utcDate(from: $0, offsetSeconds: offsetSeconds) },
            software: software,
            make: maker,
            model: model,
            lensModel: lensModel,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    /// « 2026:09:06 16:32:05 » + 7200 s → « 2026:09:06 14:32:05 ».
    ///
    /// Une date illisible rend `nil` plutôt qu'une valeur approximative :
    /// mieux vaut l'absence d'information qu'une information fausse, qui
    /// serait lue comme une incohérence et enverrait la preuve en revue.
    static func utcDate(from local: String, offsetSeconds: Int) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        guard let asIfUTC = formatter.date(from: local) else { return nil }
        return formatter.string(from: asIfUTC.addingTimeInterval(-Double(offsetSeconds)))
    }

    /// Lit les métadonnées d'un JPEG.
    ///
    /// Ne lève jamais : sans métadonnées lisibles, on rend `nil` et le serveur
    /// lèvera son signal habituel. Une extraction ratée ne doit pas empêcher
    /// l'envoi d'une preuve — la promesse a peut-être été parfaitement tenue.
    static func extract(from jpegData: Data, now: Date = .now) -> ProofExif? {
        guard
            let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        // `OffsetTimeOriginal` n'existe que sur les appareils récents. À
        // défaut, le fuseau de l'appareil au moment de la capture est la
        // meilleure approximation disponible — la photo vient d'être prise.
        let offset = (exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
            .flatMap(parseOffset) ?? TimeZone.current.secondsFromGMT(for: now)

        let candidate = make(
            localDate: exif[kCGImagePropertyExifDateTimeOriginal] as? String,
            offsetSeconds: offset,
            software: tiff[kCGImagePropertyTIFFSoftware] as? String,
            make: tiff[kCGImagePropertyTIFFMake] as? String,
            model: tiff[kCGImagePropertyTIFFModel] as? String,
            lensModel: exif[kCGImagePropertyExifLensModel] as? String,
            pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int,
            pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int
        )

        return candidate.isEmpty ? nil : candidate
    }

    /// « +02:00 » → 7200.
    static func parseOffset(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 6 else { return nil }

        let sign = trimmed.hasPrefix("-") ? -1 : 1
        let digits = trimmed.dropFirst()
        let parts = digits.split(separator: ":")
        guard
            parts.count == 2,
            let hours = Int(parts[0]),
            let minutes = Int(parts[1])
        else { return nil }

        return sign * (hours * 3600 + minutes * 60)
    }
}
