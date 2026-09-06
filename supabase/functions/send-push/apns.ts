/**
 * Construction et envoi d'une notification APNs.
 *
 * Cette fonction ne décide de rien : la fenêtre de preuve a déjà été ouverte
 * par le cron (migration 0027), l'objectif est déjà passé en
 * `proof_window_open`, et l'échéance court déjà. Un échec de livraison est un
 * incident à journaliser, jamais un motif de changer l'état d'un objectif —
 * mettre APNs sur le chemin critique de l'argent, c'est ce que ce chantier a
 * précisément défait.
 *
 * ⚠️ Ce fichier n'a jamais tourné contre Apple : le compte Apple Developer
 * n'existe pas encore, donc ni clé `.p8`, ni `key id`, ni `team id`. La
 * signature ES256, le cache du jeton et le traitement des codes d'erreur sont
 * écrits d'après la documentation et testés unitairement, pas en conditions
 * réelles. C'est la partie de ce chantier la moins éprouvée.
 */

/** Ce qu'il faut savoir pour livrer une demande de preuve. */
export interface PushMessage {
  goalId: string;
  title: string;
  body: string;
  /** Échéance de la fenêtre de preuve, en ISO 8601. */
  proofDeadlineAt: string;
  apnsToken: string;
  /** `sandbox` ou `production`, tel qu'enregistré par l'appareil. */
  env: string;
}

export interface ApnsCredentials {
  keyId: string;
  teamId: string;
  bundleId: string;
  /** Contenu du fichier .p8, au format PEM. */
  privateKeyPem: string;
}

/**
 * Corps de la notification.
 *
 * Ne contient JAMAIS `fire_at` (invariant 4). L'instant du contrôle est
 * précisément ce que l'utilisateur ne doit pas pouvoir anticiper, et une
 * notification est inspectable sur l'appareil. Au moment où celle-ci part, la
 * fenêtre est de toute façon déjà ouverte : ce qui est utile à l'app, c'est
 * l'objectif concerné et la date de fin, pas la date de début.
 */
export function buildApnsPayload(message: PushMessage): Record<string, unknown> {
  return {
    aps: {
      alert: { title: message.title, body: message.body },
      sound: "default",
      "interruption-level": "time-sensitive",
    },
    goal_id: message.goalId,
    proof_deadline_at: message.proofDeadlineAt,
  };
}

/**
 * En-têtes de la requête APNs.
 *
 * `apns-expiration` vaut l'échéance de preuve : une notification livrée après
 * la fermeture de la fenêtre est pire qu'une notification jamais livrée — elle
 * annonce à l'utilisateur un contrôle auquel il ne peut plus répondre.
 * Sans cet en-tête, Apple garderait le message en file et pourrait le
 * distribuer bien plus tard.
 */
export function buildApnsHeaders(
  message: PushMessage,
  bundleId: string,
  bearer: string,
): Record<string, string> {
  return {
    authorization: `bearer ${bearer}`,
    "apns-topic": bundleId,
    "apns-push-type": "alert",
    "apns-priority": "10",
    "apns-expiration": String(
      Math.floor(new Date(message.proofDeadlineAt).getTime() / 1000),
    ),
    "content-type": "application/json",
  };
}

export type ApnsOutcome = "delivered" | "revoke" | "retry" | "drop";

/**
 * Que faire d'une réponse d'Apple.
 *
 * `revoke` retire l'appareil de la liste : le jeton ne désigne plus rien, le
 * garder ferait grossir `attempts` indéfiniment. `retry` laisse la ligne en
 * file. `drop` abandonne : réessayer ne changerait rien.
 */
export function classifyApnsError(status: number, reason?: string): ApnsOutcome {
  if (status >= 200 && status < 300) return "delivered";

  // 410 Gone, ou 400 BadDeviceToken : l'application a été désinstallée, ou le
  // jeton vient d'un autre environnement (sandbox contre production).
  if (status === 410) return "revoke";
  if (reason === "BadDeviceToken" || reason === "Unregistered") return "revoke";
  if (reason === "DeviceTokenNotForTopic") return "revoke";

  // Débit limité ou panne côté Apple : la file sera reprise au tour suivant.
  if (status === 429 || status >= 500) return "retry";

  // 403 (signature invalide), 400 (payload malformé) : réessayer à l'identique
  // ne peut que reproduire l'erreur.
  return "drop";
}

// --- Signature du jeton -----------------------------------------------------

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function encodeSegment(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

/**
 * Extrait les octets DER d'une clé PEM PKCS#8.
 *
 * Rend un `ArrayBuffer` et non un `Uint8Array` : `importKey` exige un
 * `BufferSource` adossé à un vrai `ArrayBuffer`, et une vue peut porter sur un
 * `SharedArrayBuffer`. Le typage refuse le raccourci, à juste titre.
 */
function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");

  const binary = atob(body);
  const buffer = new ArrayBuffer(binary.length);
  const view = new Uint8Array(buffer);
  for (let i = 0; i < binary.length; i += 1) {
    view[i] = binary.charCodeAt(i);
  }
  return buffer;
}

export function buildJwtHeader(keyId: string): Record<string, string> {
  return { alg: "ES256", kid: keyId };
}

export function buildJwtClaims(teamId: string, issuedAt: number): Record<string, unknown> {
  return { iss: teamId, iat: issuedAt };
}

/**
 * Apple refuse plus d'un jeton par tranche de vingt minutes, et rejette un
 * jeton de plus d'une heure. On en garde donc un en mémoire pendant trente
 * minutes — durée confortablement comprise entre les deux bornes.
 */
const TOKEN_TTL_MS = 30 * 60 * 1000;
let cachedToken: { value: string; expiresAt: number; keyId: string } | null = null;

/** Vide le cache. Réservé aux tests. */
export function resetTokenCache(): void {
  cachedToken = null;
}

export async function apnsBearerToken(
  credentials: ApnsCredentials,
  now: number = Date.now(),
): Promise<string> {
  if (cachedToken && cachedToken.keyId === credentials.keyId && cachedToken.expiresAt > now) {
    return cachedToken.value;
  }

  const issuedAt = Math.floor(now / 1000);
  const unsigned = `${encodeSegment(buildJwtHeader(credentials.keyId))}.${
    encodeSegment(buildJwtClaims(credentials.teamId, issuedAt))
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(credentials.privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  // WebCrypto rend déjà la signature au format concaténé r||s attendu par JWS.
  // Pas de conversion DER à faire — c'est le piège habituel d'ES256.
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(unsigned),
    ),
  );

  const token = `${unsigned}.${base64url(signature)}`;
  cachedToken = { value: token, expiresAt: now + TOKEN_TTL_MS, keyId: credentials.keyId };
  return token;
}

export function apnsHost(env: string): string {
  return env === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
}
