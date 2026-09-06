// Tests des decisions prises autour de l'appel au modele.
//
// Elles sont isolees du reseau a dessein : ce sont elles qui decident si
// quelqu'un perd de l'argent, et elles doivent pouvoir etre verifiees sans
// cle API ni image.
//
// Execution : deno test supabase/functions --allow-env --no-check

import { assertEquals } from "jsr:@std/assert@1";
import {
  checkImage,
  ESCALATION_CONFIDENCE_THRESHOLD,
  ESCALATION_MODEL,
  FIRST_PASS_MODEL,
  MAX_IMAGE_BYTES,
  shouldEscalate,
  unavailableVerdict,
} from "./policy.ts";
import { selectProvider } from "./providers.ts";
import { DEFAULT_ROUTING, routeVerdict } from "../_shared/routing.ts";
import { runAntiCheat } from "../_shared/anticheat.ts";
import type { VerdictResponse } from "../_shared/prompts.ts";

function verdict(overrides: Partial<VerdictResponse> = {}): VerdictResponse {
  return {
    verdict: "pass",
    confidence: 0.95,
    reason: "Le lit est fait.",
    spoof_suspected: false,
    ...overrides,
  };
}

// --- L'escalade -------------------------------------------------------------

Deno.test("un verdict net et assure ne coute pas un second appel", () => {
  assertEquals(shouldEscalate(verdict()), false);
  assertEquals(shouldEscalate(verdict({ verdict: "fail", confidence: 0.93 })), false);
});

Deno.test("un doute du premier passage appelle le gros modele", () => {
  assertEquals(shouldEscalate(verdict({ verdict: "uncertain", confidence: 0.9 })), true);
});

Deno.test("une confiance faible appelle le gros modele", () => {
  // Sans cette escalade, la preuve partirait en revue humaine sans avoir ete
  // relue par le meilleur modele disponible — on paierait un humain pour un
  // travail qu'une machine savait faire.
  assertEquals(shouldEscalate(verdict({ confidence: 0.5 })), true);
});

Deno.test("une suspicion de fraude merite le meilleur regard disponible", () => {
  // C'est l'accusation la plus lourde qu'on puisse porter contre quelqu'un.
  assertEquals(shouldEscalate(verdict({ spoof_suspected: true })), true);
});

Deno.test("le seuil d'escalade est celui du routage", () => {
  // Escalader en deca d'un seuil different produirait des verdicts qui partent
  // en revue humaine sans etre passes par le gros modele.
  assertEquals(ESCALATION_CONFIDENCE_THRESHOLD, DEFAULT_ROUTING.confidenceThreshold);
});

Deno.test("le premier passage est le modele le moins cher", () => {
  assertEquals(FIRST_PASS_MODEL, "claude-haiku-4-5");
  assertEquals(ESCALATION_MODEL, "claude-sonnet-5");
});

// --- Les images qu'on ne sait pas lire --------------------------------------

Deno.test("une photo JPEG ordinaire est exploitable", () => {
  assertEquals(checkImage("image/jpeg", 400_000).usable, true);
});

Deno.test("un format que le modele ne lit pas n'est pas un rejet", () => {
  // Le bucket accepte le HEIC, pas le modele. L'utilisateur a peut-etre tenu
  // sa promesse : c'est notre chaine qui ne sait pas la lire.
  const check = checkImage("image/heic", 400_000);
  assertEquals(check.usable, false);
  assertEquals(check.reason?.includes("image/heic"), true);
});

Deno.test("une image trop lourde pour l'API n'est pas un rejet", () => {
  assertEquals(checkImage("image/jpeg", MAX_IMAGE_BYTES + 1).usable, false);
});

Deno.test("une image vide n'est pas un rejet", () => {
  assertEquals(checkImage("image/jpeg", 0).usable, false);
});

// --- L'indisponibilite ------------------------------------------------------

Deno.test("une panne de notre cote ne rejette jamais", () => {
  // Invariant 2 applique a la lettre : `uncertain`, que routing.ts enverra en
  // revue humaine. Un `fail` couterait de l'argent a quelqu'un pour une panne
  // dont il n'est pas responsable.
  assertEquals(unavailableVerdict("API 500").verdict, "uncertain");
  assertEquals(unavailableVerdict("API 500").confidence, 0);
  assertEquals(unavailableVerdict("API 500").spoof_suspected, false);
});

Deno.test("un modele indisponible ne rejette jamais la preuve", () => {
  // La chaine complete : verdict de repli -> routage.
  //
  // La revue humaine etant fermee (2026-09-06), une panne du fournisseur
  // VALIDE desormais la preuve au lieu de la faire relire. C'est lourd de
  // consequences et c'est assume : l'invariant 2 interdit de debiter
  // quelqu'un sur un doute, et une panne de notre cote est le doute le moins
  // imputable a l'utilisateur qui soit. Le jour ou un tableau de revue
  // existera, ce cas doit y retourner.
  const antiCheat = runAntiCheat({
    capturedAt: "2026-09-02T07:02:00Z",
    serverReceivedAt: "2026-09-02T07:02:30Z",
    windowOpenedAt: "2026-09-02T07:00:00Z",
    proofDeadlineAt: "2026-09-02T07:15:00Z",
    exif: null,
    imageSha256: "a".repeat(64),
    duplicateCount: 0,
    onDevicePrecheck: null,
  });

  const decision = routeVerdict({
    verdict: unavailableVerdict("aucune cle de modele configuree"),
    antiCheat,
    stakeAmountCents: 500,
  });

  assertEquals(decision.route, "validated");
  // Le motif garde la trace de ce qui aurait du etre relu. Ici c'est le
  // signal d'anti-triche qui parle en premier — la photo de ce cas n'a pas
  // d'EXIF — avant meme que l'incertitude du modele soit examinee.
  assertEquals(decision.reason, "no_review:anticheat_flags:exif_missing");
});

// --- Le choix du fournisseur ------------------------------------------------

Deno.test("sans aucune cle, chaque preuve part en revue humaine", () => {
  // Couteux, et voulu : inventer un verdict faute de modele serait la pire
  // chose que ce code puisse faire.
  assertEquals(selectProvider(() => undefined).name, "unavailable");
});

Deno.test("une cle de test fait tourner la chaine sur Gemini", () => {
  const env = (key: string) => (key === "GEMINI_API_KEY" ? "cle-de-test" : undefined);
  assertEquals(selectProvider(env).name, "gemini");
});

Deno.test("la cle de test ne detourne jamais la production de Claude", () => {
  // Les deux cles presentes : Claude gagne. C'est la cible de production, et
  // le prompt systeme est regle pour lui.
  const env = (key: string) =>
    ({ ANTHROPIC_API_KEY: "cle-prod", GEMINI_API_KEY: "cle-de-test" })[key];
  assertEquals(selectProvider(env).name, "anthropic");
});

Deno.test("le fournisseur indisponible rend un verdict sans appeler personne", async () => {
  const answer = await selectProvider(() => undefined).verdict({
    systemPrompt: "s",
    userPrompt: "u",
    imageBase64: "",
    mediaType: "image/jpeg",
  });
  assertEquals(answer.verdict, "uncertain");
  assertEquals(answer.model, "none");
});
