/**
 * Décision finale : que fait-on du verdict du modèle ?
 *
 * Principe directeur : on ne débite jamais sur un doute. Le coût d'une revue
 * humaine (0,20 à 0,50 €) est sans commune mesure avec celui d'un débit
 * injustifié, qui coûte un client et une réputation.
 */

import type { AntiCheatResult } from "./anticheat.ts";
import type { VerdictResponse } from "./prompts.ts";

export type Route = "validated" | "rejected" | "human_review";

export interface RoutingConfig {
  /** Confiance minimale pour trancher sans intervention humaine. */
  confidenceThreshold: number;
  /**
   * Au-delà de ce montant, tout verdict passe par un humain.
   *
   * `null` désactive le critère : le montant ne déclenche plus jamais de
   * revue, et seuls la confiance du modèle, les signaux d'anti-triche et
   * l'échantillon aléatoire peuvent encore escalader. C'est un choix
   * délibéré (2026-09-06), pas un oubli — le mécanisme reste en place pour
   * qu'un seuil puisse être remis sans réécrire le routage.
   */
  humanReviewStakeThresholdCents: number | null;
  /** Part des validations relue au hasard, pour la dissuasion. */
  randomAuditRate: number;
}

export const DEFAULT_ROUTING: RoutingConfig = {
  confidenceThreshold: 0.8,
  // Desactive : le montant seul ne fait plus escalader. Voir la decision du
  // 2026-09-06 dans CLAUDE.md.
  humanReviewStakeThresholdCents: null,
  randomAuditRate: 0.05,
};

export interface RoutingInput {
  verdict: VerdictResponse;
  antiCheat: AntiCheatResult;
  stakeAmountCents: number;
  config?: RoutingConfig;
  /** Injectable pour rendre les tests déterministes. */
  random?: () => number;
}

export interface RoutingDecision {
  route: Route;
  reason: string;
}

export function routeVerdict(input: RoutingInput): RoutingDecision {
  const config = input.config ?? DEFAULT_ROUTING;
  const random = input.random ?? Math.random;
  const { verdict, antiCheat } = input;

  // Fraude établie par construction : preuve hors fenêtre, image déjà
  // utilisée. Aucun jugement d'image n'est nécessaire.
  if (antiCheat.hardReject) {
    return { route: "rejected", reason: antiCheat.hardReject.reason };
  }

  // Une suspicion de falsification ne suffit pas à rejeter : accuser
  // quelqu'un de fraude à tort est le pire résultat possible pour ce produit.
  if (verdict.spoof_suspected) {
    return { route: "human_review", reason: "spoof_suspected" };
  }

  if (antiCheat.flags.length > 0) {
    return {
      route: "human_review",
      reason: `anticheat_flags:${antiCheat.flags.join(",")}`,
    };
  }

  if (verdict.verdict === "uncertain") {
    return { route: "human_review", reason: "model_uncertain" };
  }

  if (verdict.confidence < config.confidenceThreshold) {
    return {
      route: "human_review",
      reason: `low_confidence:${verdict.confidence.toFixed(2)}`,
    };
  }

  // Sur les mises élevées, l'erreur coûte trop cher pour être automatisée —
  // quand le seuil existe. `null` le désactive volontairement.
  if (
    config.humanReviewStakeThresholdCents !== null &&
    input.stakeAmountCents >= config.humanReviewStakeThresholdCents
  ) {
    return { route: "human_review", reason: "high_stake" };
  }

  if (verdict.verdict === "fail") {
    return { route: "rejected", reason: "model_fail" };
  }

  // Relecture aléatoire de validations : sans elle, un fraudeur qui trouve
  // une faille du modèle peut l'exploiter indéfiniment sans être vu.
  if (random() < config.randomAuditRate) {
    return { route: "human_review", reason: "random_audit" };
  }

  return { route: "validated", reason: "model_pass" };
}
