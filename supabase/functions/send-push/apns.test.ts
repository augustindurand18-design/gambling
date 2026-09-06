// Tests de la livraison APNs.
//
// Ce fichier n'a jamais tourne contre Apple : sans compte Apple Developer, ni
// cle .p8 ni identifiants n'existent. Ces tests couvrent donc ce qui est
// verifiable sans lui — la forme du message, le choix du transport, le
// traitement des codes d'erreur — et pas la livraison elle-meme.
//
// Execution : deno test supabase/functions --allow-env --no-check

import { assertEquals } from "jsr:@std/assert@1";
import {
  buildApnsHeaders,
  buildApnsPayload,
  buildJwtClaims,
  buildJwtHeader,
  classifyApnsError,
  type PushMessage,
} from "./apns.ts";
import { readApnsCredentials, selectTransport } from "./transport.ts";
import { CLOCK_SKEW_TOLERANCE_SEC, MAX_CAPTURE_DELAY_SEC } from "../_shared/anticheat.ts";

const DEADLINE = "2026-09-02T07:15:00.000Z";

function message(overrides: Partial<PushMessage> = {}): PushMessage {
  return {
    goalId: "bbbb2222-0000-0000-0000-000000000001",
    title: "C'est le moment",
    body: "Aller a la salle — tu as 15 minutes pour envoyer ta preuve.",
    proofDeadlineAt: DEADLINE,
    apnsToken: "aa00bb11cc22",
    env: "sandbox",
    ...overrides,
  };
}

// --- Le contenu du message --------------------------------------------------

Deno.test("le message ne revele jamais l'instant du controle", () => {
  // Invariant 4 : une notification est inspectable sur l'appareil. Y glisser
  // fire_at rendrait le prochain controle previsible, donc la preuve
  // preparable a l'avance — ce qui vide la fenetre surprise de son sens.
  const serialized = JSON.stringify(buildApnsPayload(message()));
  assertEquals(serialized.includes("fire_at"), false);
});

Deno.test("le message porte l'objectif et son echeance", () => {
  const payload = buildApnsPayload(message()) as Record<string, unknown>;
  assertEquals(payload.goal_id, "bbbb2222-0000-0000-0000-000000000001");
  assertEquals(payload.proof_deadline_at, DEADLINE);
});

Deno.test("une demande de preuve interrompt la mise en veille", () => {
  // Sans « time-sensitive », le mode concentration retiendrait la notification
  // et la fenetre de quinze minutes se fermerait sans que l'utilisateur ait rien vu.
  const payload = buildApnsPayload(message()) as { aps: Record<string, unknown> };
  assertEquals(payload.aps["interruption-level"], "time-sensitive");
});

Deno.test("la notification expire avec la fenetre de preuve", () => {
  // Une notification livree apres la fermeture de la fenetre est pire que pas
  // de notification : elle annonce un controle auquel on ne peut plus repondre.
  const headers = buildApnsHeaders(message(), "com.augustindurand.gage", "jeton");
  assertEquals(headers["apns-expiration"], String(Date.parse(DEADLINE) / 1000));
});

Deno.test("l'en-tete nomme le bundle et demande une alerte prioritaire", () => {
  const headers = buildApnsHeaders(message(), "com.augustindurand.gage", "jeton");
  assertEquals(headers["apns-topic"], "com.augustindurand.gage");
  assertEquals(headers["apns-push-type"], "alert");
  assertEquals(headers["apns-priority"], "10");
  assertEquals(headers.authorization, "bearer jeton");
});

// --- Le jeton ---------------------------------------------------------------

Deno.test("l'en-tete du jeton annonce ES256 et la cle utilisee", () => {
  assertEquals(buildJwtHeader("K1D2E3"), { alg: "ES256", kid: "K1D2E3" });
});

Deno.test("les revendications du jeton portent l'equipe et l'instant d'emission", () => {
  assertEquals(buildJwtClaims("T34MID", 1_756_800_000), {
    iss: "T34MID",
    iat: 1_756_800_000,
  });
});

// --- Le traitement des reponses d'Apple -------------------------------------

Deno.test("un jeton peri fait sortir l'appareil de la liste", () => {
  // Sans revocation, la ligne serait reprise a chaque tour jusqu'a epuiser
  // ses tentatives, pour un appareil qui n'existe plus.
  assertEquals(classifyApnsError(410), "revoke");
  assertEquals(classifyApnsError(400, "BadDeviceToken"), "revoke");
  assertEquals(classifyApnsError(400, "Unregistered"), "revoke");
});

Deno.test("une panne d'Apple laisse la notification en file", () => {
  assertEquals(classifyApnsError(429), "retry");
  assertEquals(classifyApnsError(500), "retry");
  assertEquals(classifyApnsError(503), "retry");
});

Deno.test("une erreur de notre cote ne se rejoue pas a l'identique", () => {
  // 403 : signature invalide. 400 sans motif connu : message malforme.
  // Reessayer le meme envoi ne peut que reproduire l'erreur.
  assertEquals(classifyApnsError(403, "InvalidProviderToken"), "drop");
  assertEquals(classifyApnsError(400, "PayloadTooLarge"), "drop");
});

Deno.test("une reponse favorable est une livraison", () => {
  assertEquals(classifyApnsError(200), "delivered");
});

// --- Le choix du transport --------------------------------------------------

Deno.test("sans identifiants APNs, la chaine reste exercable", () => {
  // C'est ce qui rend ce chantier verifiable de bout en bout avant l'ouverture
  // du compte Apple Developer.
  assertEquals(readApnsCredentials(() => undefined), null);
  assertEquals(selectTransport(() => undefined).name, "log");
});

Deno.test("des identifiants incomplets ne suffisent pas", () => {
  // Une cle sans identifiant d'equipe produirait un jeton refuse par Apple, et
  // des lignes en echec plutot qu'un repli lisible.
  const partiel = (key: string) =>
    key === "APNS_KEY_ID" ? "K1D2E3" : undefined;
  assertEquals(readApnsCredentials(partiel), null);
  assertEquals(selectTransport(partiel).name, "log");
});

Deno.test("les identifiants au complet font basculer sur Apple", () => {
  const complet = (key: string) =>
    ({
      APNS_KEY_ID: "K1D2E3",
      APNS_TEAM_ID: "T34MID",
      APNS_BUNDLE_ID: "com.augustindurand.gage",
      APNS_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----",
    })[key];
  assertEquals(selectTransport(complet).name, "apns");
});

// --- L'alignement des quinze minutes ----------------------------------------

Deno.test("le delai de soumission reste le meme des trois cotes", () => {
  // La meme duree vit dans app.proof_window_seconds(), ici, et dans
  // ProofWindow.duration cote iOS. Aucune verification automatique ne detecte
  // une derive : ce test assene le litteral pour qu'un changement unilateral
  // fasse echouer quelque chose plutot que de passer inapercu.
  assertEquals(MAX_CAPTURE_DELAY_SEC, 900);
  assertEquals(CLOCK_SKEW_TOLERANCE_SEC, 120);
});
