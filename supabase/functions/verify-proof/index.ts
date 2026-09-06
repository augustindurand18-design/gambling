/**
 * Vérification d'une preuve : anti-triche, modèle, routage, verdict.
 *
 * C'est la fonction qui décide qu'un objectif est tenu ou perdu, donc celle
 * qui déclenche — ou non — un débit. Trois règles la gouvernent, toutes
 * tirées de l'invariant 2 :
 *
 *   1. le modèle ne rejette jamais seul : sa réponse traverse `routing.ts` ;
 *   2. toute indisponibilité de notre côté part en revue humaine, jamais en
 *      rejet — clé absente, API en panne, image illisible ;
 *   3. seuls deux cas se passent du modèle, et ce sont des fraudes établies :
 *      preuve reçue avant l'ouverture de la fenêtre, image déjà utilisée.
 *
 * Elle n'est pas encore planifiée. On l'appelle à la main pendant le
 * développement (voir CONTRIBUTING.md) ; elle traite alors toute la file des
 * preuves en attente.
 */

import { adminClient, errorResponse, json, transitionGoal } from "../_shared/db.ts";
import { runAntiCheat } from "../_shared/anticheat.ts";
import { buildSystemPrompt, buildUserPrompt } from "../_shared/prompts.ts";
import { routeVerdict } from "../_shared/routing.ts";
import { checkImage, unavailableVerdict } from "./policy.ts";
import { selectProvider, type VisionAnswer } from "./providers.ts";

/** Fenêtre de contestation, miroir de `app.dispute_window_hours()`. */
const DISPUTE_WINDOW_HOURS = 48;

/** Une preuve trop vieille n'est plus à vérifier automatiquement. */
const MAX_AGE_HOURS = 72;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return errorResponse("Méthode non autorisée", 405);
  }

  const db = adminClient();
  const provider = selectProvider((key) => Deno.env.get(key));

  // Un identifiant précis, ou toute la file.
  let proofId: string | null = null;
  try {
    proofId = (await req.json())?.proof_id ?? null;
  } catch {
    proofId = null;
  }

  let query = db
    .from("proofs")
    .select(
      "id, goal_id, user_id, storage_path, image_sha256, captured_at, " +
        "server_received_at, exif, ondevice_precheck, " +
        "goals!inner(title, proof_instruction, goal_type, state, timezone, " +
        "window_opened_at, proof_deadline_at, stakes(amount_cents))",
    )
    .is("final_verdict", null)
    .eq("goals.state", "proof_submitted")
    .gt("server_received_at", new Date(Date.now() - MAX_AGE_HOURS * 3600_000).toISOString())
    .limit(50);

  if (proofId) query = query.eq("id", proofId);

  const { data: pending, error } = await query;

  if (error) {
    return errorResponse(`Lecture des preuves impossible : ${error.message}`, 500);
  }

  const outcomes: Record<string, number> = {};

  for (const proof of pending ?? []) {
    try {
      const route = await verifyOne(db, provider, proof);
      outcomes[route] = (outcomes[route] ?? 0) + 1;
    } catch (cause) {
      // Une preuve qui explose ne doit pas emporter la file. Elle reste en
      // `proof_submitted` et sera reprise au prochain passage.
      console.error(`[verify-proof] preuve ${proof.id} : ${cause}`);
      outcomes.error = (outcomes.error ?? 0) + 1;
    }
  }

  return json({ provider: provider.name, examined: pending?.length ?? 0, outcomes });
});

// deno-lint-ignore no-explicit-any
async function verifyOne(db: any, provider: ReturnType<typeof selectProvider>, proof: any) {
  const goal = proof.goals;

  // L'objectif entre en vérification avant tout appel externe : si la fonction
  // meurt en plein vol, l'état dit où elle en était.
  await transitionGoal(db, {
    goalId: proof.goal_id,
    toState: "ai_verifying",
    actor: "verify-proof",
    reason: "verification automatique",
  });

  // Doublon d'image, toutes personnes confondues : c'est la seule fraude qui
  // se constate sans regarder la photo.
  const { count } = await db
    .from("proofs")
    .select("id", { count: "exact", head: true })
    .eq("image_sha256", proof.image_sha256)
    .neq("id", proof.id);

  const antiCheat = runAntiCheat({
    capturedAt: proof.captured_at,
    serverReceivedAt: proof.server_received_at,
    windowOpenedAt: goal.window_opened_at,
    proofDeadlineAt: goal.proof_deadline_at,
    exif: proof.exif,
    imageSha256: proof.image_sha256,
    duplicateCount: count ?? 0,
    onDevicePrecheck: proof.ondevice_precheck,
  });

  const stakeAmountCents = goal.stakes?.amount_cents ?? 0;

  // Fraude établie : inutile de payer un appel au modèle pour la confirmer.
  let answer: VisionAnswer;
  if (antiCheat.hardReject) {
    answer = {
      ...unavailableVerdict(`rejet immediat : ${antiCheat.hardReject.reason}`),
      verdict: "fail",
      reason: `Rejet automatique : ${antiCheat.hardReject.reason}`,
      confidence: 1,
      model: "none",
      raw: null,
    };
  } else {
    answer = await askModel(db, provider, proof, goal, antiCheat.flags);
  }

  const decision = routeVerdict({ verdict: answer, antiCheat, stakeAmountCents });

  const finalVerdict = decision.route === "validated"
    ? "pass"
    : decision.route === "rejected"
    ? "fail"
    : null; // la revue humaine tranchera

  await db
    .from("proofs")
    .update({
      anticheat: antiCheat,
      ai_verdict: answer.verdict,
      ai_confidence: answer.confidence,
      ai_reason: answer.reason,
      ai_spoof_suspected: answer.spoof_suspected,
      ai_model: answer.model,
      ai_raw: answer.raw,
      ai_completed_at: new Date().toISOString(),
      final_verdict: finalVerdict,
      decided_by: finalVerdict ? "ai" : null,
      decided_at: finalVerdict ? new Date().toISOString() : null,
    })
    .eq("id", proof.id);

  await applyRoute(db, proof.goal_id, decision.route, decision.reason);
  return decision.route;
}

// deno-lint-ignore no-explicit-any
async function askModel(
  // deno-lint-ignore no-explicit-any
  db: any,
  provider: ReturnType<typeof selectProvider>,
  // deno-lint-ignore no-explicit-any
  proof: any,
  // deno-lint-ignore no-explicit-any
  goal: any,
  flags: string[],
): Promise<VisionAnswer> {
  if (!proof.storage_path) {
    return { ...unavailableVerdict("photo purgee"), model: "none", raw: null };
  }

  const { data: file, error } = await db.storage.from("proofs").download(proof.storage_path);
  if (error || !file) {
    return { ...unavailableVerdict("photo illisible"), model: "none", raw: null };
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  const mediaType = file.type || "image/jpeg";

  const usability = checkImage(mediaType, bytes.byteLength);
  if (!usability.usable) {
    return { ...unavailableVerdict(usability.reason!), model: "none", raw: null };
  }

  return await provider.verdict({
    systemPrompt: buildSystemPrompt(),
    userPrompt: buildUserPrompt({
      goalTitle: goal.title,
      proofInstruction: goal.proof_instruction,
      goalType: goal.goal_type,
      antiCheatFlags: flags,
      windowOpenedAtLocal: localTime(goal.window_opened_at, goal.timezone),
      timezone: goal.timezone,
    }),
    imageBase64: base64(bytes),
    mediaType,
  });
}

/**
 * Applique le verdict à l'objectif.
 *
 * Une validation va jusqu'à `closed_kept` : sans ça, l'objectif resterait en
 * `validated` sans que personne ne vienne jamais le clore. L'échantillon
 * aléatoire anti-fraude est déjà pris en compte en amont par `routing.ts`,
 * qui route vers la revue humaine plutôt que vers la validation.
 */
// deno-lint-ignore no-explicit-any
async function applyRoute(db: any, goalId: string, route: string, reason: string) {
  if (route === "validated") {
    await transitionGoal(db, {
      goalId,
      toState: "validated",
      actor: "verify-proof",
      reason,
    });
    await transitionGoal(db, {
      goalId,
      toState: "closed_kept",
      actor: "verify-proof",
      reason: "objectif tenu",
    });
    return;
  }

  if (route === "rejected") {
    // L'échéance de contestation doit être posée ici : sans elle,
    // `app.close_expired_goals()` ne clôturera jamais cet objectif — elle
    // exige explicitement une échéance non nulle.
    await transitionGoal(db, {
      goalId,
      toState: "rejected",
      actor: "verify-proof",
      reason,
      fields: {
        dispute_deadline_at: new Date(Date.now() + DISPUTE_WINDOW_HOURS * 3600_000)
          .toISOString(),
      },
    });
    return;
  }

  await transitionGoal(db, {
    goalId,
    toState: "human_review",
    actor: "verify-proof",
    reason,
    fields: { human_review_reason: reason },
  });
}

/** L'heure telle que l'utilisateur l'a vécue, pour le prompt. */
function localTime(instant: string | null, timezone: string): string | null {
  if (!instant) return null;
  try {
    return new Date(instant).toLocaleString("fr-FR", { timeZone: timezone });
  } catch {
    return null;
  }
}

/** Encodage base64 sans dépassement de pile sur une image de plusieurs Mo. */
function base64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}
