/**
 * Enregistrement de la carte, une seule fois, à l'onboarding.
 *
 * Rend de quoi ouvrir le PaymentSheet natif. La carte n'est jamais vue par
 * notre serveur : elle va de l'application à Stripe directement, et il ne
 * nous revient qu'un identifiant de moyen de paiement.
 *
 * `usage: "off_session"` est le point central. Il déclare à la banque, dès
 * l'enregistrement, que cette carte servira à des débits différés initiés par
 * le marchand. C'est ce qui permet, le jour d'un objectif raté, de débiter
 * sans que l'utilisateur soit devant son téléphone — et c'est aussi ce qui
 * fait que la 3DS est demandée maintenant plutôt que là-bas, au pire moment.
 */

import { adminClient, errorResponse, json, requireUser } from "../_shared/db.ts";
import { stripeClient } from "../_shared/stripe.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return errorResponse("Méthode non autorisée", 405);
  }

  const caller = await requireUser(req);
  if (!caller) {
    return errorResponse("Authentification requise", 401);
  }

  const db = adminClient();
  const stripe = stripeClient();

  const { data: profile, error } = await db
    .from("profiles")
    .select("stripe_customer_id, email, display_name")
    .eq("user_id", caller.userId)
    .single();

  if (error || !profile) {
    return errorResponse("Profil introuvable", 404);
  }

  let customerId = profile.stripe_customer_id as string | null;

  if (!customerId) {
    // `idempotencyKey` sur l'identifiant utilisateur : deux appels
    // simultanés — deux taps, une reprise réseau — ne doivent pas créer deux
    // clients Stripe pour la même personne.
    const customer = await stripe.customers.create(
      {
        email: profile.email ?? undefined,
        name: profile.display_name ?? undefined,
        metadata: { supabase_user_id: caller.userId },
      },
      { idempotencyKey: `customer:${caller.userId}` },
    );

    customerId = customer.id;

    const { error: linkError } = await db.rpc("set_stripe_customer", {
      p_user_id: caller.userId,
      p_customer_id: customerId,
    });

    if (linkError) {
      return errorResponse(`Rattachement du client impossible : ${linkError.message}`, 500);
    }
  }

  // Clé éphémère : sans elle, le PaymentSheet ne peut pas afficher les moyens
  // de paiement déjà enregistrés par cette personne.
  const ephemeralKey = await stripe.ephemeralKeys.create(
    { customer: customerId },
    { apiVersion: "2026-07-29.dahlia" },
  );

  const setupIntent = await stripe.setupIntents.create({
    customer: customerId,
    // Pas de `payment_method_types` : les moyens acceptés se règlent dans le
    // tableau de bord. Restreindre ici figerait le choix dans le code.
    usage: "off_session",
    metadata: { supabase_user_id: caller.userId },
  });

  return json({
    setup_intent_client_secret: setupIntent.client_secret,
    ephemeral_key: ephemeralKey.secret,
    customer_id: customerId,
    publishable_key: Deno.env.get("STRIPE_PUBLISHABLE_KEY") ?? null,
  });
});
