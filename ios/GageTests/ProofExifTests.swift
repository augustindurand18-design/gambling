import Foundation
import Testing
@testable import Gage

/// Les metadonnees jointes a une preuve.
///
/// Ce que ces tests protegent tient en une phrase : sans EXIF exploitable,
/// `runAntiCheat` leve un signal et `routeVerdict` envoie la preuve en revue
/// humaine. Cent pour cent des preuves y passeraient, a 0,20-0,50 € piece, et
/// la verification automatique ne servirait a rien. Le defaut a ete trouve en
/// faisant tourner `verify-proof` contre une vraie preuve.
@Suite("Métadonnées d'une preuve")
struct ProofExifTests {

    // MARK: - Conversion de fuseau

    @Test("Une date de prise de vue est convertie en UTC")
    func utcConversion() {
        // L'EXIF stocke l'heure locale sans fuseau, et `parseExifDate` côté
        // serveur la lit comme de l'UTC. Sans cette conversion, une photo
        // prise en France serait décalée d'une à deux heures — bien au-delà
        // de la tolérance de cinq minutes — et lèverait `exif_date_mismatch`
        // sur chaque preuve honnête.
        #expect(
            ProofExif.utcDate(from: "2026:09:06 16:32:05", offsetSeconds: 7200)
                == "2026:09:06 14:32:05"
        )
    }

    @Test("Un fuseau à l'ouest décale dans l'autre sens")
    func westOfGreenwich() {
        #expect(
            ProofExif.utcDate(from: "2026:01:15 08:00:00", offsetSeconds: -18000)
                == "2026:01:15 13:00:00"
        )
    }

    @Test("Un décalage nul laisse la date inchangée")
    func noOffset() {
        #expect(
            ProofExif.utcDate(from: "2026:09:06 14:32:05", offsetSeconds: 0)
                == "2026:09:06 14:32:05"
        )
    }

    @Test("Une conversion peut franchir minuit")
    func acrossMidnight() {
        #expect(
            ProofExif.utcDate(from: "2026:09:07 00:30:00", offsetSeconds: 7200)
                == "2026:09:06 22:30:00"
        )
    }

    @Test("Une date illisible ne devient pas une date approximative")
    func unreadableDate() {
        // Mieux vaut l'absence d'information qu'une information fausse : une
        // date inventée serait lue comme une incohérence et enverrait la
        // preuve en revue humaine.
        #expect(ProofExif.utcDate(from: "hier matin", offsetSeconds: 0) == nil)
        #expect(ProofExif.utcDate(from: "2026-09-06T14:32:05Z", offsetSeconds: 0) == nil)
    }

    // MARK: - Lecture du décalage

    @Test("Le décalage EXIF est lu dans les deux sens")
    func parseOffset() {
        #expect(ProofExif.parseOffset("+02:00") == 7200)
        #expect(ProofExif.parseOffset("-05:00") == -18000)
        #expect(ProofExif.parseOffset("+05:30") == 19800)
        #expect(ProofExif.parseOffset("+00:00") == 0)
    }

    @Test("Un décalage malformé est ignoré")
    func badOffset() {
        #expect(ProofExif.parseOffset("") == nil)
        #expect(ProofExif.parseOffset("+2h") == nil)
        #expect(ProofExif.parseOffset("plus tard") == nil)
    }

    // MARK: - Assemblage et minimisation

    @Test("Les clés envoyées sont celles que l'anti-triche lit")
    func encodingKeys() throws {
        // `anticheat.ts` cherche `Software` et `DateTimeOriginal`. Un
        // renommage silencieux rendrait l'EXIF illisible côté serveur, qui
        // conclurait à son absence — exactement le défaut qu'on répare.
        let exif = ProofExif.make(
            localDate: "2026:09:06 16:32:05",
            offsetSeconds: 7200,
            software: "18.0",
            make: "Apple",
            model: "iPhone 15 Pro",
            lensModel: "iPhone 15 Pro back camera",
            pixelWidth: 3024,
            pixelHeight: 4032
        )

        let json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(exif)) as? [String: Any]
        )
        #expect(json["Software"] as? String == "18.0")
        #expect(json["DateTimeOriginal"] as? String == "2026:09:06 14:32:05")
    }

    @Test("Aucune coordonnée GPS n'est transmise")
    func noLocation() throws {
        // Minimisation RGPD : l'EXIF brut d'une photo porte le lieu où elle a
        // été prise. On n'en a pas besoin pour vérifier une promesse, donc on
        // ne le collecte pas. La liste blanche est la garantie — un jour
        // quelqu'un sera tenté d'envoyer le dictionnaire entier.
        let exif = ProofExif.make(
            localDate: "2026:09:06 16:32:05", offsetSeconds: 7200,
            software: "18.0", make: "Apple", model: "iPhone 15 Pro",
            lensModel: nil, pixelWidth: nil, pixelHeight: nil
        )

        let encoded = try String(decoding: JSONEncoder().encode(exif), as: UTF8.self)
        #expect(!encoded.contains("GPS"))
        #expect(!encoded.contains("Latitude"))
        #expect(!encoded.contains("Longitude"))
    }

    @Test("Un logiciel étranger reste transmis tel quel")
    func foreignSoftware() {
        // C'est au serveur de lever `exif_foreign_software`, pas au client de
        // filtrer ce qui l'accuserait. L'appareil ne se juge pas lui-même.
        let exif = ProofExif.make(
            localDate: nil, offsetSeconds: 0,
            software: "Photoshop 26.0", make: nil, model: nil,
            lensModel: nil, pixelWidth: nil, pixelHeight: nil
        )
        #expect(exif.software == "Photoshop 26.0")
    }

    @Test("Un EXIF entièrement vide se reconnaît comme tel")
    func emptyIsEmpty() {
        // Envoyer un objet vide ferait croire à une extraction réussie ; le
        // champ nul dit la vérité, et le serveur lèvera son signal.
        let empty = ProofExif.make(
            localDate: nil, offsetSeconds: 0, software: nil, make: nil,
            model: nil, lensModel: nil, pixelWidth: nil, pixelHeight: nil
        )
        #expect(empty.isEmpty)

        let filled = ProofExif.make(
            localDate: nil, offsetSeconds: 0, software: "18.0", make: nil,
            model: nil, lensModel: nil, pixelWidth: nil, pixelHeight: nil
        )
        #expect(!filled.isEmpty)
    }

    @Test("Une image sans métadonnées ne fait pas échouer l'extraction")
    func extractionNeverThrows() {
        // Une extraction ratée ne doit jamais empêcher l'envoi d'une preuve :
        // la promesse a peut-être été parfaitement tenue.
        #expect(ProofExif.extract(from: Data()) == nil)
        #expect(ProofExif.extract(from: Data("pas une image".utf8)) == nil)
    }
}
