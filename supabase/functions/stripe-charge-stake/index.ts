/**
 * Encaissement d'une mise perdue.
 *
 * Cette fonction ne décide rien. Quand elle s'exécute, la machine à états a
 * déjà tranché : l'objectif est en `closed_failed`, soit parce qu'aucune
 * preuve n'est arrivée et que la fenêtre de contestation est passée, soit
 * parce qu'un humain a confirmé l'échec. Elle exécute une décision prise
 * ailleurs, et c'est ce qui la rend sûre.
 *
 * Le débit part hors session : personne n'est devant son téléphone. Le
 * consentement date de l'engagement, il est horodaté et immuable
 * (`consents`), et le mandat bancaire vient du SetupIntent en
 * `usage: off_session`.
 *
 * Elle n'est pas planifiée. On l'appelle à la main pendant le développement ;
 * en production ce sera un job, une fois le rythme d'encaissement arbitré.
 */

import type Stripe from "npm:stripe@22.4.0";
import { adminClient, errorResponse, json } from "../_shared/db.ts";
import { CURRENCY, isFailure, requiresAction, stripeClient } from "../_shared/stripe.ts";

/** Au-delà, on cesse d'insister : la ligne reste visible avec son motif. */
const MAX_ATTEMPTS = 4;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return errorResponse("Méthode non autorisée", 405);
  }

  const db = adminClient();
  const stripe = stripeClient();

  let goalId: string | null = null;
  try {
    goalId = (await req.json())?.goal_id ?? null;
  } catch {
    goalId = null;
  }

  // Sans identifiant, toute la file. Les objectifs déjà en `charge_failed`
  // sont repris : une carte mise à jour doit pouvoir débloquer la situation.
  let query = db
    .from("goals")
    .select("id, state")
    .in("state", ["closed_failed", "charge_failed"])
    .limit(50);

  if (goalId) query = query.eq("id", goalId);

  const { data: due, error } = await query;
  if (error) {
    return errorResponse(`Lecture de la file impossible : ${error.message}`, 500);
  }

  const outcomes: Record<string, number> = {};

  for (const goal of due ?? []) {
    try {
      const result = await chargeOne(db, stripe, goal.id);
      outcomes[result] = (outcomes[result] ?? 0) + 1;
    } catch (cause) {
      console.error(`[stripe-charge-stake] objectif ${goal.id} : ${cause}`);
      outcomes.error = (outcomes.error ?? 0) + 1;
    }
  }

  return json({ examined: due?.length ?? 0, outcomes });
});

// deno-lint-ignore no-explicit-any
async function chargeOne(db: any, stripe: Stripe, goalId: string): Promise<string> {
  // La base fige le partage, crée la charge et passe l'objectif en
  // `charge_pending`. Tout est fait avant d'appeler Stripe : si le réseau
  // tombe pendant l'appel, l'état dit qu'un débit était en cours.
  const { data: rows, error } = await db.rpc("begin_stake_charge", { p_goal_id: goalId });
  if (error) throw new Error(`begin_stake_charge : ${error.message}`);

  const charge = Array.isArray(rows) ? rows[0] : rows;
  if (!charge) throw new Error("begin_stake_charge n'a rien rendu");

  if (charge.attempt_count > MAX_ATTEMPTS) {
    return "abandoned";
  }

  let intent: Stripe.PaymentIntent;
  try {
    intent = await stripe.paymentIntents.create(
      {
        amount: charge.amount_cents,
        currency: CURRENCY,
        customer: charge.stripe_customer_id,
        payment_method: charge.payment_method_id,
        // Hors session : le débit est initié par nous, pas par l'utilisateur.
        // Sans cette mention, la banque exigerait une authentification à tous
        // les coups, et aucun débit différé ne passerait jamais.
        off_session: true,
        confirm: true,
        description: "Gage — mise engagée sur un objectif non tenu",
        metadata: { goal_id: goalId, charge_id: charge.charge_id },
      },
      // Une reprise après coupure ne doit pas débiter deux fois. La clé
      // inclut le numéro de tentative : une relance délibérée après échec
      // reste possible, un rejeu accidentel non.
      { idempotencyKey: `charge:${charge.charge_id}:${charge.attempt_count}` },
    );
  } catch (cause) {
    // Stripe lève sur un refus en confirmation immédiate. Le PaymentIntent
    // existe malgré tout, et c'est lui qui porte le motif.
    const stripeError = cause as Stripe.errors.StripeError;
    const failed = stripeError.payment_intent;

    if (failed?.id) {
      await db.rpc("attach_charge_intent", {
        p_charge_id: charge.charge_id,
        p_payment_intent_id: failed.id,
      });
      await db.rpc("settle_charge_failed", {
        p_payment_intent_id: failed.id,
        p_failure_code: stripeError.code ?? "card_declined",
        p_failure_message: stripeError.message ?? null,
        p_requires_action: requiresAction(failed.status),
      });
      return requiresAction(failed.status) ? "requires_action" : "failed";
    }

    throw cause;
  }

  await db.rpc("attach_charge_intent", {
    p_charge_id: charge.charge_id,
    p_payment_intent_id: intent.id,
  });

  // Le webhook fera foi. On applique quand même l'issue tout de suite : les
  // RPC sont idempotentes, et attendre le webhook laisserait l'utilisateur
  // devant un état faux pendant plusieurs secondes.
  if (intent.status === "succeeded") {
    await db.rpc("settle_charge_succeeded", { p_payment_intent_id: intent.id });
    return "succeeded";
  }

  if (isFailure(intent.status)) {
    await db.rpc("settle_charge_failed", {
      p_payment_intent_id: intent.id,
      p_failure_code: requiresAction(intent.status)
        ? "authentication_required"
        : intent.last_payment_error?.code ?? "payment_failed",
      p_failure_message: requiresAction(intent.status)
        ? "La banque demande une authentification."
        : intent.last_payment_error?.message ?? null,
      p_requires_action: requiresAction(intent.status),
    });
    return requiresAction(intent.status) ? "requires_action" : "failed";
  }

  return "processing";
}
