// Tests des decisions prises autour d'un debit.
//
// Le cas qui compte est celui de l'authentification bancaire. Il a ete verifie
// contre le vrai Stripe avec `pm_card_authenticationRequired`, et le premier
// jet se trompait : voir le commentaire de `requiresAction`.
//
// Execution : deno test supabase/functions --allow-env --no-check

import { assertEquals } from "jsr:@std/assert@1";
import { CURRENCY, isFailure, requiresAction, STRIPE_API_VERSION } from "./stripe-policy.ts";

Deno.test("un paiement abouti n'est pas un echec", () => {
  assertEquals(isFailure("succeeded"), false);
});

Deno.test("un paiement encore en cours n'est pas un echec", () => {
  // Le webhook tranchera. Conclure a l'echec ici gelerait la creation
  // d'objectifs de quelqu'un dont le debit va finalement passer.
  assertEquals(isFailure("processing"), false);
});

Deno.test("tout le reste est un echec", () => {
  assertEquals(isFailure("requires_payment_method"), true);
  assertEquals(isFailure("requires_action"), true);
  assertEquals(isFailure("canceled"), true);
});

Deno.test("le code d'erreur fait foi sur l'authentification bancaire", () => {
  // Verifie contre le vrai Stripe : sur un refus hors session, il leve avec
  // `code: "authentication_required"` mais laisse le PaymentIntent dans un
  // statut qui n'est pas `requires_action`. Se fier au seul statut rangeait
  // ces refus parmi les cartes refusees, et l'utilisateur aurait lu « change
  // de carte » alors qu'il devait confirmer aupres de sa banque.
  assertEquals(requiresAction("requires_payment_method", "authentication_required"), true);
  assertEquals(requiresAction(undefined, "authentication_required"), true);
});

Deno.test("le statut suffit quand aucun code n'accompagne le refus", () => {
  assertEquals(requiresAction("requires_action"), true);
  assertEquals(requiresAction("requires_confirmation"), true);
});

Deno.test("une carte refusee n'est pas une authentification a fournir", () => {
  // Les deux mènent au meme blocage, mais pas au meme message : dans un cas
  // il faut changer de carte, dans l'autre confirmer aupres de sa banque.
  assertEquals(requiresAction("requires_payment_method", "card_declined"), false);
});

Deno.test("la devise et la version d'API sont figees", () => {
  // La version epinglee doit rester celle du compte : sans epinglage, une
  // evolution cote Stripe changerait la forme des objets recus par le webhook
  // sans qu'aucun deploiement ne l'annonce, et ce webhook decide de debits.
  assertEquals(CURRENCY, "eur");
  assertEquals(STRIPE_API_VERSION, "2026-07-29.dahlia");
});
