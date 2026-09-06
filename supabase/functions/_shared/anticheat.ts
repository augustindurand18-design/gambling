/**
 * Contrôles anti-triche appliqués côté serveur, avant tout appel au modèle.
 *
 * Principe : l'appareil est une source non fiable. `captured_at`, la position
 * et l'EXIF sont déclarés par le client et peuvent être falsifiés. Seuls
 * `server_received_at` et l'instant d'ouverture de fenêtre — décidé par le
 * serveur — font foi.
 */

export interface AntiCheatInput {
  capturedAt: string | null;
  serverReceivedAt: string;
  windowOpenedAt: string | null;
  proofDeadlineAt: string | null;
  exif: Record<string, unknown> | null;
  imageSha256: string;
  /** Nombre de preuves déjà enregistrées avec ce hash, toutes personnes confondues. */
  duplicateCount: number;
  onDevicePrecheck: {
    screenshotScore?: number;
    screenDetected?: boolean;
    passed?: boolean;
  } | null;
}

export interface AntiCheatResult {
  /** Écart entre la prise de vue déclarée et la réception serveur. */
  captureDelaySec: number | null;
  /** La prise de vue déclarée tombe-t-elle dans la fenêtre autorisée ? */
  insideWindow: boolean;
  /** L'EXIF est-il cohérent avec la prise de vue déclarée ? */
  exifConsistent: boolean | null;
  /** Cette image a-t-elle déjà servi de preuve ? */
  hashDuplicate: boolean;
  /** La preuve a-t-elle été soumise avant même l'ouverture de la fenêtre ? */
  submittedBeforeWindow: boolean;
  /** Motifs de suspicion, à joindre au prompt du modèle. */
  flags: string[];
  /**
   * Rejet immédiat, sans appel au modèle. Réservé aux cas où la fraude est
   * établie par construction, pas simplement suspectée.
   */
  hardReject: { reason: string } | null;
}

/**
 * Au-delà de cet écart, la photo n'a manifestement pas été prise à l'instant demandé.
 *
 * Exportée parce que la même durée vit à trois endroits — ici,
 * `app.proof_window_seconds()` côté base et `ProofWindow.duration` côté iOS —
 * et qu'aucune vérification automatique ne détecte une dérive entre les trois.
 * Un test l'assène de chaque côté.
 */
export const MAX_CAPTURE_DELAY_SEC = 15 * 60;

/** Tolérance d'horloge entre l'appareil et le serveur. Miroir de `app.proof_clock_grace_seconds()`. */
export const CLOCK_SKEW_TOLERANCE_SEC = 120;

export function runAntiCheat(input: AntiCheatInput): AntiCheatResult {
  const flags: string[] = [];
  let hardReject: { reason: string } | null = null;

  const received = new Date(input.serverReceivedAt).getTime();
  const captured = input.capturedAt ? new Date(input.capturedAt).getTime() : null;
  const windowOpened = input.windowOpenedAt
    ? new Date(input.windowOpenedAt).getTime()
    : null;
  const deadline = input.proofDeadlineAt
    ? new Date(input.proofDeadlineAt).getTime()
    : null;

  // --- Fenêtre de preuve -----------------------------------------------
  // Une preuve reçue avant l'ouverture de la fenêtre est impossible de bonne
  // foi : l'utilisateur ne connaît pas l'instant du contrôle. C'est le signal
  // de fraude le plus net dont on dispose.
  const submittedBeforeWindow = windowOpened === null || received < windowOpened;
  if (windowOpened === null) {
    hardReject = { reason: "window_never_opened" };
  } else if (received < windowOpened) {
    hardReject = { reason: "submitted_before_window_opened" };
  } else if (deadline !== null && received > deadline) {
    hardReject = { reason: "submitted_after_deadline" };
  }

  // --- Réutilisation d'image -------------------------------------------
  // La même photo ne peut jamais valider deux objectifs, même chez deux
  // personnes différentes.
  const hashDuplicate = input.duplicateCount > 0;
  if (hashDuplicate && !hardReject) {
    hardReject = { reason: "duplicate_image" };
  }

  // --- Cohérence temporelle --------------------------------------------
  let captureDelaySec: number | null = null;
  if (captured !== null) {
    captureDelaySec = Math.round((received - captured) / 1000);

    if (captureDelaySec < -CLOCK_SKEW_TOLERANCE_SEC) {
      flags.push("capture_timestamp_in_future");
    }
    if (captureDelaySec > MAX_CAPTURE_DELAY_SEC) {
      flags.push("capture_much_older_than_submission");
    }
    if (windowOpened !== null && captured < windowOpened - CLOCK_SKEW_TOLERANCE_SEC) {
      flags.push("captured_before_window_opened");
    }
  } else {
    flags.push("no_capture_timestamp");
  }

  const insideWindow = captured !== null &&
    windowOpened !== null &&
    captured >= windowOpened - CLOCK_SKEW_TOLERANCE_SEC &&
    (deadline === null || captured <= deadline + CLOCK_SKEW_TOLERANCE_SEC);

  // --- EXIF -------------------------------------------------------------
  const exifConsistent = checkExif(input.exif, captured, flags);

  // --- Pré-filtre embarqué ---------------------------------------------
  // Indicatif seulement : le modèle tranche. Un pré-filtre trop strict
  // pénaliserait des preuves valides (photo d'un écran de voiture, par ex.).
  if (input.onDevicePrecheck?.screenDetected) {
    flags.push("ondevice_screen_detected");
  }
  if ((input.onDevicePrecheck?.screenshotScore ?? 0) > 0.7) {
    flags.push("ondevice_high_screenshot_score");
  }

  return {
    captureDelaySec,
    insideWindow,
    exifConsistent,
    hashDuplicate,
    submittedBeforeWindow,
    flags,
    hardReject,
  };
}

function checkExif(
  exif: Record<string, unknown> | null,
  capturedMs: number | null,
  flags: string[],
): boolean | null {
  if (!exif || Object.keys(exif).length === 0) {
    // Une capture par l'appareil photo produit toujours de l'EXIF. Son absence
    // suggère une image retravaillée ou fabriquée.
    flags.push("exif_missing");
    return false;
  }

  const software = String(exif.Software ?? exif.software ?? "").toLowerCase();
  if (software && !/apple|ios|iphone|camera/.test(software)) {
    flags.push("exif_foreign_software");
  }

  const original = exif.DateTimeOriginal ?? exif.dateTimeOriginal;
  if (!original) {
    flags.push("exif_no_original_date");
    return false;
  }

  if (capturedMs !== null) {
    const exifMs = parseExifDate(String(original));
    if (exifMs === null) {
      flags.push("exif_unparseable_date");
      return false;
    }
    // Plus de 5 minutes d'écart entre l'EXIF et la date déclarée : incohérent.
    if (Math.abs(exifMs - capturedMs) > 5 * 60 * 1000) {
      flags.push("exif_date_mismatch");
      return false;
    }
  }

  return true;
}

/** L'EXIF utilise "YYYY:MM:DD HH:MM:SS", que Date ne sait pas lire tel quel. */
function parseExifDate(raw: string): number | null {
  const match = raw.match(/^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
  if (!match) {
    const fallback = Date.parse(raw);
    return Number.isNaN(fallback) ? null : fallback;
  }
  const [, y, mo, d, h, mi, s] = match;
  const parsed = Date.parse(`${y}-${mo}-${d}T${h}:${mi}:${s}Z`);
  return Number.isNaN(parsed) ? null : parsed;
}
