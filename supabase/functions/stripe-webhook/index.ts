/**
 * Webhook Stripe.
 *
 * C'est ici qu'arrive le sort d'un débit. Trois précautions, dans cet ordre.
 *
 * **La signature d'abord.** Sans vérification, n'importe qui pourrait poster
 * un `payment_intent.succeeded` et solder une dette qui n'a jamais été payée.
 * Rien n'est lu du corps avant que la signature ne soit validée.
 *
 * **L'idempotence ensuite.** Stripe rejoue : même événement, plusieurs fois,
 * parfois des heures après. `stripe_events` garde ce qui a été traité. Les
 * RPC de 0029 sont idempotentes de leur côté — deux ceintures valent mieux
 * qu'une quand il s'agit de compter l'argent deux fois.
 *
 * **Un 200 même en cas d'erreur applicative.** Si on rend une erreur, Stripe
 * rejoue en boucle exponentielle pendant trois jours. Pour un événement qu'on
 * ne sait pas traiter, mieux vaut l'accuser, le journaliser, et le reprendre
 * à la main. On ne rend une erreur que si le rejeu a une chance d'aider.
 */

import type Stripe from "npm:stripe@22.4.0";
import { adminClient, errorResponse, json } from "../_shared/db.ts";
import { stripeClient } from "../_shared/stripe.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return errorResponse("Méthode non autorisée", 405);
  }

  const signature = req.headers.get("stripe-signature");
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");

  if (!signature || !secret) {
    return errorResponse("Signature ou secret de webhook manquant", 400);
  }

  const stripe = stripeClient();
  const payload = await req.text();

  let event: Stripe.Event;
  try {
    // `constructEventAsync` et non `constructEvent` : la variante synchrone
    // s'appuie sur le crypto de Node, absent de l'Edge Runtime.
    event = await stripe.webhooks.constructEventAsync(payload, signature, secret);
  } catch (cause) {
    // Signature invalide : ce n'est pas un incident à rejouer, c'est un appel
    // qui n'aurait pas dû arriver.
    console.error(`[stripe-webhook] signature refusée : ${cause}`);
    return errorResponse("Signature invalide", 400);
  }

  const db = adminClient();

  // Déjà vu ? La table a `id` en clé primaire : l'insertion échoue sur un
  // rejeu, ce qui est précisément le signal recherché.
  const { error: seenError } = await db
    .from("stripe_events")
    .insert({ id: event.id, type: event.type, payload: event as unknown });

  if (seenError) {
    // 23505 : violation d'unicité, donc rejeu. Tout le reste est une vraie
    // panne de base, et là un rejeu de Stripe peut aider.
    if (seenError.code === "23505") {
      return json({ received: true, duplicate: true });
    }
    return errorResponse(`Journalisation impossible : ${seenError.message}`, 500);
  }

  try {
    await handle(db, event);
  } catch (cause) {
    // L'événement est déjà journalisé : le rejouer ne ferait que retomber sur
    // le doublon. On accuse réception et on laisse une trace à reprendre.
    console.error(`[stripe-webhook] ${event.type} (${event.id}) : ${cause}`);
    return json({ received: true, handled: false, error: String(cause) });
  }

  return json({ received: true, handled: true });
});

// deno-lint-ignore no-explicit-any
async function handle(db: any, event: Stripe.Event): Promise<void> {
  switch (event.type) {
    // --- Enregistrement de la carte -----------------------------------------

    case "setup_intent.succeeded": {
      const intent = event.data.object as Stripe.SetupIntent;
      const userId = intent.metadata?.supabase_user_id;
      const paymentMethodId = typeof intent.payment_method === "string"
        ? intent.payment_method
        : intent.payment_method?.id;

      if (!userId || !paymentMethodId) {
        throw new Error("SetupIntent sans utilisateur ou sans moyen de paiement");
      }

      const stripe = stripeClient();
      const method = await stripe.paymentMethods.retrieve(paymentMethodId);

      // La carte devient celle du client par défaut : sans ça, un débit hors
      // session ne saurait pas laquelle utiliser.
      if (typeof intent.customer === "string") {
        await stripe.customers.update(intent.customer, {
          invoice_settings: { default_payment_method: paymentMethodId },
        });
      }

      await rpc(db, "set_default_payment_method", {
        p_user_id: userId,
        p_customer_id: typeof intent.customer === "string" ? intent.customer : null,
        p_payment_method_id: paymentMethodId,
        p_last4: method.card?.last4 ?? null,
        p_brand: method.card?.brand ?? null,
        p_exp_month: method.card?.exp_month ?? null,
        p_exp_year: method.card?.exp_year ?? null,
      });
      return;
    }

    // --- Sort d'un débit ----------------------------------------------------

    case "payment_intent.succeeded": {
      const intent = event.data.object as Stripe.PaymentIntent;
      await rpc(db, "settle_charge_succeeded", { p_payment_intent_id: intent.id });
      return;
    }

    case "payment_intent.payment_failed": {
      const intent = event.data.object as Stripe.PaymentIntent;
      await rpc(db, "settle_charge_failed", {
        p_payment_intent_id: intent.id,
        p_failure_code: intent.last_payment_error?.code ?? "payment_failed",
        p_failure_message: intent.last_payment_error?.message ?? null,
        p_requires_action: false,
      });
      return;
    }

    // La banque réclame une authentification. Traité comme un échec de carte
    // (décision du 2026-09-06), la distinction restant visible dans
    // `charges.status` pour que le message affiché soit le bon.
    case "payment_intent.requires_action": {
      const intent = event.data.object as Stripe.PaymentIntent;
      await rpc(db, "settle_charge_failed", {
        p_payment_intent_id: intent.id,
        p_failure_code: "authentication_required",
        p_failure_message: "La banque demande une authentification.",
        p_requires_action: true,
      });
      return;
    }

    // --- La carte disparaît -------------------------------------------------

    // Carte détachée ou expirée côté Stripe : on ne peut plus débiter. Le
    // profil doit cesser de prétendre le contraire, sinon `commit_goal`
    // laisserait engager de l'argent sur un moyen de paiement fantôme.
    case "payment_method.detached": {
      const method = event.data.object as Stripe.PaymentMethod;
      await db
        .from("profiles")
        .update({
          default_payment_method_id: null,
          pm_last4: null,
          pm_brand: null,
          pm_exp_month: null,
          pm_exp_year: null,
        })
        .eq("default_payment_method_id", method.id);
      return;
    }

    default:
      // Les autres événements sont journalisés dans `stripe_events` et
      // ignorés. C'est volontaire : s'abonner large et traiter étroit rend
      // les événements consultables le jour où on en a besoin.
      return;
  }
}

// deno-lint-ignore no-explicit-any
async function rpc(db: any, name: string, params: Record<string, unknown>) {
  const { error } = await db.rpc(name, params);
  if (error) throw new Error(`${name} : ${error.message}`);
}
