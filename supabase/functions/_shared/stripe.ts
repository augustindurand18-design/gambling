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

import { STRIPE_API_VERSION } from "./stripe-policy.ts";
export { STRIPE_API_VERSION };

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

// Les regles qui decident d'un blocage vivent dans `stripe-policy.ts`, sans
// dependance npm, pour rester executables par `deno test` en local.
export {
  CURRENCY,
  isFailure,
  type PaymentIntentStatus,
  requiresAction,
} from "./stripe-policy.ts";
