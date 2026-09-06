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
  /**
   * La revue humaine est-elle ouverte ?
   *
   * `false` la ferme entièrement : tout ce qui y serait parti est **validé**.
   * Le sens n'est pas un choix de confort — l'invariant 2 dit qu'on ne débite
   * jamais sur un doute, et il n'y a personne pour lever celui-ci. Ces
   * preuves finissaient déjà validées 24 h plus tard par
   * `app.close_stale_reviews()` : les valider tout de suite est le même
   * résultat, annoncé honnêtement.
   *
   * Ce que cela coûte : une falsification soupçonnée est validée elle aussi,
   * et la relecture aléatoire ne dissuade plus rien. À rouvrir le jour où un
   * tableau de revue existe. Décision du 2026-09-06.
   */
  humanReviewEnabled: boolean;
}

export const DEFAULT_ROUTING: RoutingConfig = {
  confidenceThreshold: 0.8,
  // Desactive : le montant seul ne fait plus escalader. Voir la decision du
  // 2026-09-06 dans CLAUDE.md.
  humanReviewStakeThresholdCents: null,
  randomAuditRate: 0.05,
  humanReviewEnabled: false,
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

  /**
   * Escalade vers un humain, ou décision automatique si ce poste n'est
   * pas tenu.
   *
   * Sans relecteur, on **suit le modèle** : il a regardé l'image, et
   * l'ignorer reviendrait à valider une photo dont il vient de dire qu'elle
   * ne montre pas la promesse. C'est exactement ce qui s'est produit le
   * 2026-09-06 — une photo d'ordinateur validée pour une séance de sport,
   * parce que l'EXIF manquant escaladait avant que le verdict soit lu.
   *
   * Un doute — modèle incertain, indisponible, peu sûr de lui — reste
   * tranché en faveur de l'utilisateur : l'invariant 2 interdit de débiter
   * sur un doute. Mais un « non » franc du modèle n'est pas un doute.
   *
   * Le motif garde la trace de ce qui aurait dû être relu.
   */
  const escalate = (reason: string): RoutingDecision => {
    if (config.humanReviewEnabled) {
      return { route: "human_review", reason };
    }
    if (verdict.verdict === "fail" && verdict.confidence >= config.confidenceThreshold) {
      return { route: "rejected", reason: `no_review:${reason}` };
    }
    return { route: "validated", reason: `no_review:${reason}` };
  };

  // Fraude établie par construction : preuve hors fenêtre, image déjà
  // utilisée. Aucun jugement d'image n'est nécessaire.
  if (antiCheat.hardReject) {
    return { route: "rejected", reason: antiCheat.hardReject.reason };
  }

  // Une suspicion de falsification ne suffit pas à rejeter : accuser
  // quelqu'un de fraude à tort est le pire résultat possible pour ce produit.
  if (verdict.spoof_suspected) {
    return escalate("spoof_suspected");
  }

  if (antiCheat.flags.length > 0) {
    return escalate(`anticheat_flags:${antiCheat.flags.join(",")}`);
  }

  if (verdict.verdict === "uncertain") {
    return escalate("model_uncertain");
  }

  if (verdict.confidence < config.confidenceThreshold) {
    return escalate(`low_confidence:${verdict.confidence.toFixed(2)}`);
  }

  // Sur les mises élevées, l'erreur coûte trop cher pour être automatisée —
  // quand le seuil existe. `null` le désactive volontairement.
  if (
    config.humanReviewStakeThresholdCents !== null &&
    input.stakeAmountCents >= config.humanReviewStakeThresholdCents
  ) {
    return escalate("high_stake");
  }

  if (verdict.verdict === "fail") {
    return { route: "rejected", reason: "model_fail" };
  }

  // Relecture aléatoire de validations : sans elle, un fraudeur qui trouve
  // une faille du modèle peut l'exploiter indéfiniment sans être vu. Le tirage
  // n'a lieu que si quelqu'un relit — sinon il ne ferait que retarder une
  // validation certaine.
  if (config.humanReviewEnabled && random() < config.randomAuditRate) {
    return { route: "human_review", reason: "random_audit" };
  }

  return { route: "validated", reason: "model_pass" };
}
