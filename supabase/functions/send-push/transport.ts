/**
 * Choix du moyen de livraison.
 *
 * Le compte Apple Developer n'existe pas encore, donc aucune clé APNs n'est
 * configurée. Plutôt que de laisser la chaîne inerte jusque-là, un transport
 * de repli journalise ce qui serait parti — sous une forme directement
 * rejouable avec `xcrun simctl push`. C'est ce qui rend tout ce chantier
 * vérifiable de bout en bout aujourd'hui, sur simulateur.
 *
 * Le jour où les variables APNs existent, le transport bascule sans qu'aucune
 * autre ligne ne change.
 */

import {
  apnsBearerToken,
  type ApnsCredentials,
  apnsHost,
  buildApnsHeaders,
  buildApnsPayload,
  classifyApnsError,
  type ApnsOutcome,
  type PushMessage,
} from "./apns.ts";

export interface PushResult {
  outcome: ApnsOutcome;
  detail: string;
}

export interface PushTransport {
  readonly name: "apns" | "log";
  send(message: PushMessage): Promise<PushResult>;
}

/** Lit les identifiants APNs de l'environnement, ou rend null s'ils manquent. */
export function readApnsCredentials(
  env: (key: string) => string | undefined,
): ApnsCredentials | null {
  const keyId = env("APNS_KEY_ID");
  const teamId = env("APNS_TEAM_ID");
  const bundleId = env("APNS_BUNDLE_ID");
  const privateKeyPem = env("APNS_PRIVATE_KEY");

  if (!keyId || !teamId || !bundleId || !privateKeyPem) return null;

  return { keyId, teamId, bundleId, privateKeyPem };
}

export function apnsTransport(credentials: ApnsCredentials): PushTransport {
  return {
    name: "apns",
    async send(message: PushMessage): Promise<PushResult> {
      const bearer = await apnsBearerToken(credentials);
      const url = `${apnsHost(message.env)}/3/device/${message.apnsToken}`;

      let response: Response;
      try {
        response = await fetch(url, {
          method: "POST",
          headers: buildApnsHeaders(message, credentials.bundleId, bearer),
          body: JSON.stringify(buildApnsPayload(message)),
        });
      } catch (error) {
        // Panne réseau : la file sera reprise au tour suivant.
        return { outcome: "retry", detail: `réseau : ${error}` };
      }

      if (response.status >= 200 && response.status < 300) {
        return { outcome: "delivered", detail: "livrée" };
      }

      const text = await response.text();
      let reason: string | undefined;
      try {
        reason = JSON.parse(text)?.reason;
      } catch {
        reason = undefined;
      }

      return {
        outcome: classifyApnsError(response.status, reason),
        detail: `${response.status} ${reason ?? text}`.trim(),
      };
    },
  };
}

/**
 * Transport de repli.
 *
 * Journalise une commande `xcrun simctl push` prête à coller : c'est ainsi
 * qu'on exerce le routage dans l'application sans compte Apple. Cela ne teste
 * évidemment pas la livraison, seulement ce que l'app fait du message.
 */
export function logTransport(): PushTransport {
  return {
    name: "log",
    send(message: PushMessage): Promise<PushResult> {
      const payload = JSON.stringify({
        ...buildApnsPayload(message),
        "Simulator Target Bundle": "com.augustindurand.gage",
      });

      console.log(
        `[send-push] APNs non configuré, notification non envoyée.\n` +
          `  objectif : ${message.goalId}\n` +
          `  échéance : ${message.proofDeadlineAt}\n` +
          `  rejouer  : echo '${payload}' > /tmp/gage.apns && ` +
          `xcrun simctl push booted com.augustindurand.gage /tmp/gage.apns`,
      );

      return Promise.resolve({
        outcome: "delivered",
        detail: "journalisée (APNs non configuré)",
      });
    },
  };
}

export function selectTransport(
  env: (key: string) => string | undefined,
): PushTransport {
  const credentials = readApnsCredentials(env);
  return credentials ? apnsTransport(credentials) : logTransport();
}
