/**
 * Client Stripe partagé.
 *
 * La clé n'existe que côté serveur (`supabase secrets set`). L'application
 * iOS ne connaît que la clé publiable, qui ne sait rien faire d'autre que
 * présenter un formulaire de carte.
 *
 * Une clé restreinte (`rk_…`) est préférable à une clé secrète (`sk_…`) : ce
 * code n'a besoin que des clients, des SetupIntents et des PaymentIntents.
 */

import Stripe from "npm:stripe@22.4.0";

/**
 * Version d'API figée.
 *
 * Sans épinglage, une évolution côté Stripe changerait la forme des objets
 * reçus par le webhook sans qu'aucun déploiement de notre côté ne l'annonce —
 * et ce webhook décide de débits.
 */
export const STRIPE_API_VERSION = "2026-07-29.dahlia";

let cached: Stripe | null = null;

export function stripeClient(): Stripe {
  if (cached) return cached;

  const key = Deno.env.get("STRIPE_SECRET_KEY");
  if (!key) {
    throw new Error(
      "STRIPE_SECRET_KEY est requise. En local : supabase/.env ; en ligne : supabase secrets set.",
    );
  }

  cached = new Stripe(key, {
    apiVersion: STRIPE_API_VERSION as Stripe.LatestApiVersion,
    httpClient: Stripe.createFetchHttpClient(),
  });

  return cached;
}

/** Réservé aux tests, qui construisent leur propre client. */
export function resetStripeClient(): void {
  cached = null;
}

/**
 * Devise unique du produit. Les mises sont en euros, le marché est la France.
 */
export const CURRENCY = "eur";

/**
 * Le débit d'une mise perdue est une opération initiée par le marchand : le
 * client n'est pas devant son téléphone au moment où elle part.
 *
 * `off_session: true` le déclare à la banque, ce qui est à la fois exact et
 * nécessaire — sans cette mention, une SCA serait exigée à tous les coups.
 * Avec, elle reste possible mais rare.
 */
export const OFF_SESSION_PAYMENT: Pick<
  Stripe.PaymentIntentCreateParams,
  "off_session" | "confirm"
> = {
  off_session: true,
  confirm: true,
};

/**
 * Faut-il traiter cette issue comme un échec ?
 *
 * Décision du 2026-09-06 : une authentification exigée par la banque est
 * traitée comme un échec de carte — le montant devient un solde dû et la
 * création d'objectifs est gelée. La distinction est conservée pour le
 * message affiché, pas pour le traitement.
 */
export function isFailure(status: Stripe.PaymentIntent.Status): boolean {
  return status !== "succeeded" && status !== "processing";
}

/** La banque demande-t-elle une authentification ? */
export function requiresAction(status: Stripe.PaymentIntent.Status): boolean {
  return status === "requires_action" || status === "requires_confirmation";
}
