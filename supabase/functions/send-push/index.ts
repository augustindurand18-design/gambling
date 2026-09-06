/**
 * Livraison des demandes de preuve.
 *
 * Cette fonction ne fait que livrer. La fenêtre a déjà été ouverte par
 * `app.tick_notifications()` (migration 0027), l'objectif est déjà en
 * `proof_window_open` et son échéance court : rien de ce qui se passe ici ne
 * change l'état d'un objectif, et donc rien ne peut faire perdre de l'argent à
 * quelqu'un. C'est délibéré — voir l'en-tête de 0027.
 *
 * Elle n'est pas encore planifiée : l'appeler depuis Postgres demanderait
 * `net.http_post` avec une clé de service, or `[db.vault]` est commenté dans
 * `config.toml` et le dépôt est public. On l'invoque à la main pendant le
 * développement (voir CONTRIBUTING.md).
 */

import { adminClient, errorResponse, json } from "../_shared/db.ts";
import type { PushMessage } from "./apns.ts";
import { selectTransport } from "./transport.ts";

/** Au-delà, on cesse d'insister : la ligne restera visible avec son erreur. */
const MAX_ATTEMPTS = 5;

/** Une demande de preuve d'hier n'a plus aucun sens à être livrée. */
const MAX_AGE_HOURS = 24;

/**
 * Ce que dit une notification de verdict.
 *
 * Le montant n'y figure pas. Une notification s'affiche sur un écran
 * verrouillé, potentiellement devant d'autres personnes : ce que quelqu'un a
 * perdu ne les regarde pas.
 */
function verdictText(outcome: unknown, title: string): { title: string; body: string } {
  if (outcome === "kept") {
    return { title: "C'est validé", body: `${title} — tu as tenu, rien ne t'est débité.` };
  }
  return { title: "Preuve refusée", body: `${title} — ouvre l'app pour voir pourquoi.` };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return errorResponse("Méthode non autorisée", 405);
  }

  // La fonction est deployee avec `--no-verify-jwt` : elle est appelee par
  // Postgres, via pg_net, qui ne sait pas transporter un JWT de 215
  // caracteres sans le deformer — le portail repondait `INVALID_JWT_FORMAT`
  // meme avec la cle ecrite en dur. C'est donc elle qui controle l'appelant,
  // avec un jeton court hors de portee de ce defaut.
  //
  // Ce que ce jeton protege est mince : declencher la livraison de
  // notifications deja dues. Il n'ouvre aucune donnee et ne change aucun
  // etat. Sans `PUSH_TRIGGER_SECRET` defini, tout appel est refuse plutot
  // qu'accepte — un secret oublie ne doit pas ouvrir la porte.
  const expected = Deno.env.get("PUSH_TRIGGER_SECRET");
  if (!expected || req.headers.get("x-gage-trigger") !== expected) {
    return errorResponse("Appel non autorisé", 401);
  }

  const db = adminClient();
  const transport = selectTransport((key) => Deno.env.get(key));

  // Seuls les objectifs déjà ouverts sont annoncés. Une ligne dont le cron n'a
  // pas encore ouvert la fenêtre — parce que l'utilisateur n'a aucun appareil,
  // par exemple — n'a rien à annoncer.
  // Deux natures de message, une seule file. L'ouverture de fenêtre n'est
  // annoncée que si la fenêtre est encore ouverte — une demande d'hier n'a
  // plus de sens. Le verdict, lui, se dit quel que soit l'état courant : il
  // annonce une décision déjà prise, et la taire parce que l'objectif a
  // depuis changé d'état priverait quelqu'un de la seule nouvelle qui compte.
  const { data: pending, error } = await db
    .from("notification_schedule")
    .select("id, kind, goal_id, user_id, attempts, fire_at, payload, goals!inner(title, state, proof_deadline_at)")
    .in("kind", ["proof_window_open", "verdict"])
    .is("sent_at", null)
    .lt("attempts", MAX_ATTEMPTS)
    .gt("fire_at", new Date(Date.now() - MAX_AGE_HOURS * 3600_000).toISOString())
    .limit(200);

  if (error) {
    return errorResponse(`Lecture de la file impossible : ${error.message}`, 500);
  }

  let delivered = 0;
  let failed = 0;

  for (const row of pending ?? []) {
    const goal = row.goals as unknown as {
      title: string;
      state: string;
      proof_deadline_at: string | null;
    };

    // Une fenêtre refermée depuis n'a plus rien à annoncer : l'utilisateur
    // recevrait « tu as 15 minutes » pour une échéance déjà passée.
    if (row.kind === "proof_window_open" && goal.state !== "proof_window_open") {
      continue;
    }

    // La tentative est comptée avant l'envoi, pas après : si la fonction meurt
    // en plein vol, la ligne ne doit pas être reprise indéfiniment à l'identique.
    await db
      .from("notification_schedule")
      .update({ attempts: row.attempts + 1 })
      .eq("id", row.id);

    const { data: devices } = await db
      .from("devices")
      .select("apns_token, env")
      .eq("user_id", row.user_id)
      .eq("revoked", false);

    if (!devices || devices.length === 0) {
      await db
        .from("notification_schedule")
        .update({ last_error: "aucun appareil actif" })
        .eq("id", row.id);
      failed += 1;
      continue;
    }

    let anyDelivered = false;
    const errors: string[] = [];

    for (const device of devices) {
      const message: PushMessage = row.kind === "verdict"
        ? {
          goalId: row.goal_id,
          ...verdictText(row.payload?.outcome, goal.title),
          proofDeadlineAt: null,
          apnsToken: device.apns_token,
          env: device.env,
        }
        : {
          goalId: row.goal_id,
          title: "C'est le moment",
          body: `${goal.title} — tu as 15 minutes pour envoyer ta preuve.`,
          proofDeadlineAt: goal.proof_deadline_at ?? row.fire_at,
          apnsToken: device.apns_token,
          env: device.env,
        };

      const result = await transport.send(message);

      if (result.outcome === "delivered") {
        anyDelivered = true;
      } else if (result.outcome === "revoke") {
        // Le jeton ne désigne plus rien : le garder ferait grossir `attempts`
        // à chaque tour sans espoir d'aboutir.
        await db
          .from("devices")
          .update({ revoked: true })
          .eq("user_id", row.user_id)
          .eq("apns_token", device.apns_token);
        errors.push(`jeton révoqué : ${result.detail}`);
      } else {
        errors.push(result.detail);
      }
    }

    // Un seul appareil joint suffit : l'utilisateur est prévenu.
    if (anyDelivered) {
      await db
        .from("notification_schedule")
        .update({ sent_at: new Date().toISOString(), last_error: null })
        .eq("id", row.id);
      delivered += 1;
    } else {
      await db
        .from("notification_schedule")
        .update({ last_error: errors.join(" ; ").slice(0, 500) })
        .eq("id", row.id);
      failed += 1;
    }
  }

  return json({ transport: transport.name, delivered, failed });
});
