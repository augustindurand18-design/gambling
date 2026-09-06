/**
 * Décisions prises autour de l'appel au modèle, isolées de tout réseau.
 *
 * Tout ce qui est ici doit rester testable sans clé API et sans image :
 * quand escalader, quelles images on sait lire, et que faire quand le modèle
 * est inaccessible. Ce sont ces règles-là qui décident si quelqu'un perd de
 * l'argent, pas la mécanique HTTP qui les entoure.
 */

import type { VerdictResponse } from "../_shared/prompts.ts";

/**
 * Premier passage : le moins cher. Il doit absorber la grande majorité des
 * preuves — une photo de lit fait ne demande pas un grand raisonnement.
 */
export const FIRST_PASS_MODEL = "claude-haiku-4-5";

/**
 * Escalade. On n'y va que sur un doute, jamais par défaut : le surcoût n'est
 * justifié que là où le premier passage n'a pas su trancher.
 */
export const ESCALATION_MODEL = "claude-sonnet-5";

/**
 * En dessous de cette confiance, le premier passage n'a rien tranché du tout.
 * Aligné sur `DEFAULT_ROUTING.confidenceThreshold` de `routing.ts` : escalader
 * en deçà d'un seuil différent de celui du routage produirait des verdicts
 * qui partent en revue humaine sans avoir été relus par le gros modèle.
 */
export const ESCALATION_CONFIDENCE_THRESHOLD = 0.8;

/**
 * Faut-il un second avis ?
 *
 * On escalade sur le doute, jamais sur le verdict lui-même : un `fail` net et
 * assuré n'a pas besoin d'être relu par un modèle plus cher, il ira de toute
 * façon en contestation si l'utilisateur n'est pas d'accord.
 */
export function shouldEscalate(first: VerdictResponse): boolean {
  if (first.verdict === "uncertain") return true;
  if (first.confidence < ESCALATION_CONFIDENCE_THRESHOLD) return true;
  // Une suspicion de fraude mérite le meilleur regard disponible avant de
  // partir en revue humaine : c'est l'accusation la plus lourde qu'on puisse
  // porter contre un utilisateur.
  if (first.spoof_suspected) return true;
  return false;
}

/**
 * Formats d'image que l'API sait lire.
 *
 * HEIC est accepté par notre bucket mais pas par le modèle. L'application
 * envoie du JPEG, donc le cas ne devrait pas se produire — mais s'il se
 * produit, il faut un humain, pas un rejet.
 */
const SUPPORTED_MEDIA_TYPES = ["image/jpeg", "image/png", "image/gif", "image/webp"];

/** Limite de l'API pour une image transmise en base64. */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

export interface ImageCheck {
  usable: boolean;
  /** Motif d'inexploitabilité, à joindre au dossier de revue humaine. */
  reason: string | null;
}

/**
 * L'image peut-elle être soumise au modèle ?
 *
 * Une image inexploitable n'est jamais un rejet. L'utilisateur a peut-être
 * parfaitement tenu sa promesse ; c'est notre chaîne technique qui ne sait pas
 * la lire, et lui faire perdre sa mise pour ça serait indéfendable.
 */
export function checkImage(mediaType: string, byteLength: number): ImageCheck {
  if (!SUPPORTED_MEDIA_TYPES.includes(mediaType)) {
    return { usable: false, reason: `format illisible par le modele : ${mediaType}` };
  }
  if (byteLength > MAX_IMAGE_BYTES) {
    return { usable: false, reason: `image trop lourde : ${byteLength} octets` };
  }
  if (byteLength === 0) {
    return { usable: false, reason: "image vide" };
  }
  return { usable: true, reason: null };
}

/**
 * Verdict de repli quand le modèle n'a pas pu se prononcer — clé absente,
 * API en panne, image illisible.
 *
 * `uncertain` et non `fail` : `routing.ts` enverra ça en revue humaine.
 * C'est l'invariant 2 appliqué à la lettre — une indisponibilité de notre côté
 * ne doit jamais coûter d'argent à qui que ce soit.
 */
export function unavailableVerdict(
  reason: string,
  options: { transient?: boolean } = {},
): VerdictResponse {
  return {
    verdict: "uncertain",
    confidence: 0,
    reason: `Verification automatique indisponible : ${reason}`,
    spoof_suspected: false,
    transient: options.transient ?? false,
  };
}
