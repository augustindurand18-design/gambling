import { assertEquals } from "jsr:@std/assert@1";
import { type AntiCheatInput, runAntiCheat } from "./anticheat.ts";
import { DEFAULT_ROUTING, routeVerdict } from "./routing.ts";
import { parseVerdict } from "./prompts.ts";

const WINDOW_OPENED = "2026-09-02T07:00:00Z";
const CAPTURED = "2026-09-02T07:02:00Z";
const RECEIVED = "2026-09-02T07:02:30Z";
const DEADLINE = "2026-09-02T07:30:00Z";

function input(overrides: Partial<AntiCheatInput> = {}): AntiCheatInput {
  return {
    capturedAt: CAPTURED,
    serverReceivedAt: RECEIVED,
    windowOpenedAt: WINDOW_OPENED,
    proofDeadlineAt: DEADLINE,
    exif: { DateTimeOriginal: "2026:09:02 07:02:00", Software: "iOS 26.0" },
    imageSha256: "a".repeat(64),
    duplicateCount: 0,
    onDevicePrecheck: { screenshotScore: 0.1, screenDetected: false, passed: true },
    ...overrides,
  };
}

Deno.test("une preuve nominale ne leve aucun signal", () => {
  const result = runAntiCheat(input());
  assertEquals(result.hardReject, null);
  assertEquals(result.flags, []);
  assertEquals(result.insideWindow, true);
  assertEquals(result.exifConsistent, true);
});

Deno.test("une preuve envoyee avant l'ouverture de la fenetre est rejetee d'emblee", () => {
  // Impossible de bonne foi : l'utilisateur ne connait pas l'instant du controle.
  const result = runAntiCheat(input({
    serverReceivedAt: "2026-09-02T06:50:00Z",
  }));
  assertEquals(result.hardReject?.reason, "submitted_before_window_opened");
});

Deno.test("une fenetre jamais ouverte interdit toute preuve", () => {
  const result = runAntiCheat(input({ windowOpenedAt: null }));
  assertEquals(result.hardReject?.reason, "window_never_opened");
});

Deno.test("une preuve hors delai est rejetee", () => {
  const result = runAntiCheat(input({
    serverReceivedAt: "2026-09-02T08:00:00Z",
  }));
  assertEquals(result.hardReject?.reason, "submitted_after_deadline");
});

Deno.test("une image deja utilisee est rejetee, meme par une autre personne", () => {
  const result = runAntiCheat(input({ duplicateCount: 1 }));
  assertEquals(result.hardReject?.reason, "duplicate_image");
});

Deno.test("une photo prise bien avant la soumission est signalee", () => {
  const result = runAntiCheat(input({
    capturedAt: "2026-09-02T06:00:00Z",
  }));
  assertEquals(result.hardReject, null);
  assertEquals(result.flags.includes("capture_much_older_than_submission"), true);
  assertEquals(result.flags.includes("captured_before_window_opened"), true);
});

Deno.test("l'absence d'EXIF est signalee", () => {
  const result = runAntiCheat(input({ exif: null }));
  assertEquals(result.exifConsistent, false);
  assertEquals(result.flags.includes("exif_missing"), true);
});

Deno.test("une date EXIF incoherente avec la prise de vue est signalee", () => {
  const result = runAntiCheat(input({
    exif: { DateTimeOriginal: "2026:09:01 22:00:00", Software: "iOS 26.0" },
  }));
  assertEquals(result.exifConsistent, false);
  assertEquals(result.flags.includes("exif_date_mismatch"), true);
});

Deno.test("un leger decalage d'horloge reste tolere", () => {
  const result = runAntiCheat(input({
    capturedAt: "2026-09-02T07:03:00Z", // 30 s "dans le futur"
  }));
  assertEquals(result.flags.includes("capture_timestamp_in_future"), false);
});

// --------------------------------------------------------------- routage

const PASS = { verdict: "pass" as const, confidence: 0.95, reason: "ok", spoof_suspected: false };
const FAIL = { verdict: "fail" as const, confidence: 0.95, reason: "ko", spoof_suspected: false };

const CLEAN = runAntiCheat(input());
const never = () => 1; // desactive l'audit aleatoire

Deno.test("une validation nette est automatique sur une petite mise", () => {
  const decision = routeVerdict({
    verdict: PASS,
    antiCheat: CLEAN,
    stakeAmountCents: 500,
    random: never,
  });
  assertEquals(decision.route, "validated");
});

Deno.test("une mise elevee passe par un humain quand un seuil existe", () => {
  const decision = routeVerdict({
    verdict: PASS,
    antiCheat: CLEAN,
    stakeAmountCents: 2_000,
    config: { ...DEFAULT_ROUTING, humanReviewStakeThresholdCents: 2_000 },
    random: never,
  });
  assertEquals(decision.route, "human_review");
  assertEquals(decision.reason, "high_stake");
});

Deno.test("sans seuil, le montant seul ne fait plus escalader", () => {
  // Desactivation deliberee (2026-09-06) : le montant ne declenche plus de
  // revue. Le mecanisme reste teste juste au-dessus, pour qu'un seuil puisse
  // etre remis sans que rien n'ait pourri entre-temps.
  assertEquals(DEFAULT_ROUTING.humanReviewStakeThresholdCents, null);

  const decision = routeVerdict({
    verdict: PASS,
    antiCheat: CLEAN,
    stakeAmountCents: 10_000,
    random: never,
  });
  assertEquals(decision.route, "validated");
});

Deno.test("une suspicion de fraude ne rejette jamais directement", () => {
  // Accuser quelqu'un de fraude a tort est le pire resultat possible.
  const decision = routeVerdict({
    verdict: { ...FAIL, spoof_suspected: true },
    antiCheat: CLEAN,
    stakeAmountCents: 500,
    random: never,
  });
  assertEquals(decision.route, "human_review");
  assertEquals(decision.reason, "spoof_suspected");
});

Deno.test("un modele incertain ne rejette jamais", () => {
  const decision = routeVerdict({
    verdict: { verdict: "uncertain", confidence: 0.9, reason: "?", spoof_suspected: false },
    antiCheat: CLEAN,
    stakeAmountCents: 500,
    random: never,
  });
  assertEquals(decision.route, "human_review");
});

Deno.test("une confiance faible ne rejette jamais", () => {
  const decision = routeVerdict({
    verdict: { ...FAIL, confidence: 0.5 },
    antiCheat: CLEAN,
    stakeAmountCents: 500,
    random: never,
  });
  assertEquals(decision.route, "human_review");
});

Deno.test("un signal anti-triche fait basculer vers l'humain", () => {
  const flagged = runAntiCheat(input({ exif: null }));
  const decision = routeVerdict({
    verdict: PASS,
    antiCheat: flagged,
    stakeAmountCents: 500,
    random: never,
  });
  assertEquals(decision.route, "human_review");
});

Deno.test("une fraude etablie rejette sans consulter le modele", () => {
  const cheating = runAntiCheat(input({ duplicateCount: 3 }));
  const decision = routeVerdict({
    verdict: PASS,
    antiCheat: cheating,
    stakeAmountCents: 500,
    random: never,
  });
  assertEquals(decision.route, "rejected");
  assertEquals(decision.reason, "duplicate_image");
});

Deno.test("l'audit aleatoire relit une part des validations", () => {
  const decision = routeVerdict({
    verdict: PASS,
    antiCheat: CLEAN,
    stakeAmountCents: 500,
    random: () => 0, // tombe toujours dans l'echantillon
  });
  assertEquals(decision.route, "human_review");
  assertEquals(decision.reason, "random_audit");
});

// ------------------------------------------------------------- parsing

Deno.test("une reponse illisible devient incertaine, jamais un rejet", () => {
  for (const raw of ["", "je ne sais pas", "{cassé", "null"]) {
    const parsed = parseVerdict(raw);
    assertEquals(parsed.verdict, "uncertain");
    assertEquals(parsed.confidence, 0);
  }
});

Deno.test("un verdict inconnu devient incertain", () => {
  const parsed = parseVerdict('{"verdict":"maybe","confidence":0.9}');
  assertEquals(parsed.verdict, "uncertain");
});

Deno.test("le JSON est extrait meme entoure de texte", () => {
  const parsed = parseVerdict(
    'Voici mon analyse :\n```json\n{"verdict":"pass","confidence":0.9,"reason":"La voiture est visible","spoof_suspected":false}\n```',
  );
  assertEquals(parsed.verdict, "pass");
  assertEquals(parsed.confidence, 0.9);
  assertEquals(parsed.reason, "La voiture est visible");
});

Deno.test("une confiance hors bornes est ramenee dans l'intervalle", () => {
  assertEquals(parseVerdict('{"verdict":"pass","confidence":5}').confidence, 1);
  assertEquals(parseVerdict('{"verdict":"pass","confidence":-2}').confidence, 0);
});
