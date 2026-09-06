/**
 * Décisions prises autour d'un débit, isolées de tout réseau.
 *
 * Séparées de `stripe.ts` pour une raison pratique : celui-ci importe le SDK
 * depuis npm, que l'Edge Runtime résout mais pas `deno test` en local. Les
 * règles qui décident si quelqu'un est bloqué doivent rester exécutables par
 * la suite de tests, sans installation ni clé.
 */

/**
 * Statut d'un PaymentIntent, tel que Stripe le rend.
 *
 * Recopié plutôt qu'importé du SDK, pour garder ce fichier sans dépendance.
 */
export type PaymentIntentStatus =
  | "requires_payment_method"
  | "requires_confirmation"
  | "requires_action"
  | "processing"
  | "requires_capture"
  | "canceled"
  | "succeeded";

/** Devise unique du produit : les mises sont en euros, le marché est la France. */
export const CURRENCY = "eur";

/**
 * Version d'API figée.
 *
 * Sans épinglage, une évolution côté Stripe changerait la forme des objets
 * reçus par le webhook sans qu'aucun déploiement de notre côté ne l'annonce —
 * et ce webhook décide de débits.
 */
export const STRIPE_API_VERSION = "2026-07-29.dahlia";

/**
 * Faut-il traiter cette issue comme un échec ?
 *
 * `processing` n'en est pas un : le webhook tranchera. Conclure à l'échec ici
 * gèlerait la création d'objectifs de quelqu'un dont le débit va finalement
 * passer.
 */
export function isFailure(status: PaymentIntentStatus): boolean {
  return status !== "succeeded" && status !== "processing";
}

/**
 * La banque demande-t-elle une authentification ?
 *
 * Le code d'erreur fait foi avant le statut. Vérifié contre le vrai Stripe
 * avec `pm_card_authenticationRequired` : sur un refus hors session, il lève
 * avec `code: "authentication_required"` mais laisse le PaymentIntent dans un
 * statut qui n'est pas `requires_action`. Se fier au seul statut rangeait ces
 * refus parmi les cartes refusées, et l'utilisateur aurait lu « change de
 * carte » alors qu'il devait confirmer auprès de sa banque.
 *
 * Décision du 2026-09-06 : les deux mènent au même blocage. Seul le message
 * diffère, et c'est précisément ce que cette fonction permet de distinguer.
 */
export function requiresAction(
  status: PaymentIntentStatus | undefined,
  code?: string,
): boolean {
  if (code === "authentication_required") return true;
  return status === "requires_action" || status === "requires_confirmation";
}
