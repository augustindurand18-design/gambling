/**
 * Le modèle de vision, derrière une interface.
 *
 * La cible de production est Claude (décision du 2026-09-02, `CLAUDE.md`).
 * Gemini est là pour pouvoir exercer la chaîne pendant que le compte
 * Anthropic n'existe pas encore — même rôle que le transport de repli de
 * `send-push`, et même principe : ce qui est branché ne doit pas changer la
 * forme du reste du code.
 *
 * Aucun fournisseur ne décide seul. Sa réponse traverse ensuite `routing.ts`,
 * qui peut la renvoyer en revue humaine quel que soit son contenu.
 */

import { parseVerdict, type VerdictResponse } from "../_shared/prompts.ts";
import {
  ESCALATION_MODEL,
  FIRST_PASS_MODEL,
  shouldEscalate,
  unavailableVerdict,
} from "./policy.ts";

export interface VisionRequest {
  systemPrompt: string;
  userPrompt: string;
  /** Octets de l'image, en base64 sans en-tête. */
  imageBase64: string;
  mediaType: string;
}

export interface VisionAnswer extends VerdictResponse {
  /** Modèle ayant rendu le verdict retenu, tracé dans `proofs.ai_model`. */
  model: string;
  /** Réponse brute, conservée pour pouvoir rejuger un litige des mois après. */
  raw: unknown;
}

export interface VisionProvider {
  readonly name: "anthropic" | "gemini" | "unavailable";
  verdict(request: VisionRequest): Promise<VisionAnswer>;
}

// --- Claude ----------------------------------------------------------------

/**
 * Deux passages : Haiku d'abord, Sonnet seulement sur le doute.
 *
 * Le premier passage doit absorber l'essentiel du volume — c'est ce qui rend
 * la vérification soutenable à 5 €/mois d'abonnement. L'escalade est là pour
 * que l'économie ne se paie pas en faux rejets.
 */
export function anthropicProvider(apiKey: string): VisionProvider {
  return {
    name: "anthropic",
    async verdict(request: VisionRequest): Promise<VisionAnswer> {
      const first = await callAnthropic(apiKey, FIRST_PASS_MODEL, request);

      if (!shouldEscalate(first.parsed)) {
        return { ...first.parsed, model: FIRST_PASS_MODEL, raw: first.raw };
      }

      const second = await callAnthropic(apiKey, ESCALATION_MODEL, request);
      return {
        ...second.parsed,
        model: ESCALATION_MODEL,
        raw: { first_pass: first.raw, escalation: second.raw },
      };
    },
  };
}

async function callAnthropic(
  apiKey: string,
  model: string,
  request: VisionRequest,
): Promise<{ parsed: VerdictResponse; raw: unknown }> {
  // Appel HTTP direct plutôt que le SDK npm : l'Edge Runtime importe déjà
  // supabase-js depuis JSR, et une seconde chaîne de dépendances npm pour un
  // unique POST alourdirait le démarrage à froid d'une fonction qui doit
  // répondre pendant que l'utilisateur attend son verdict.
  let response: Response;
  try {
    response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: 1024,
        system: request.systemPrompt,
        messages: [{
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: request.mediaType,
                data: request.imageBase64,
              },
            },
            { type: "text", text: request.userPrompt },
          ],
        }],
      }),
    });
  } catch (error) {
    return { parsed: unavailableVerdict(`reseau (${error})`), raw: { error: String(error) } };
  }

  if (!response.ok) {
    const detail = await response.text();
    return {
      parsed: unavailableVerdict(`API ${response.status}`),
      raw: { status: response.status, body: detail.slice(0, 2000) },
    };
  }

  const body = await response.json();
  const text = (body?.content ?? [])
    .filter((block: { type: string }) => block.type === "text")
    .map((block: { text: string }) => block.text)
    .join("\n");

  return { parsed: parseVerdict(text), raw: body };
}

// --- Gemini (test uniquement) ----------------------------------------------

/**
 * Fournisseur de test.
 *
 * Il n'a pas d'escalade : son rôle est d'exercer la chaîne, pas de tenir la
 * qualité de vérification. Ne pas le laisser servir en production — le prompt
 * système est écrit et réglé pour Claude.
 */
export function geminiProvider(
  apiKey: string,
  // Le palier le moins cher, et suffisant pour ce qu'on lui demande :
  // verifier que la chaine tourne.
  //
  // `gemini-2.5-flash-lite` semblait le choix prudent — plus ancien, donc
  // plus stable. Google le refuse aux comptes recents : « no longer available
  // to new users ». Constate en appelant l'API, pas en lisant la
  // documentation. `GEMINI_MODEL` permet d'en essayer un autre sans toucher
  // au code, ce qui servira le jour ou celui-ci sera ferme a son tour.
  model = "gemini-3.5-flash-lite",
): VisionProvider {
  return {
    name: "gemini",
    async verdict(request: VisionRequest): Promise<VisionAnswer> {
      const url =
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

      let response: Response;
      try {
        response = await fetch(url, {
          method: "POST",
          headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
          body: JSON.stringify({
            systemInstruction: { parts: [{ text: request.systemPrompt }] },
            contents: [{
              role: "user",
              parts: [
                { inline_data: { mime_type: request.mediaType, data: request.imageBase64 } },
                { text: request.userPrompt },
              ],
            }],
            generationConfig: { responseMimeType: "application/json" },
          }),
        });
      } catch (error) {
        return {
          ...unavailableVerdict(`reseau (${error})`),
          model,
          raw: { error: String(error) },
        };
      }

      if (!response.ok) {
        const detail = await response.text();
        return {
          ...unavailableVerdict(`API ${response.status}`),
          model,
          raw: { status: response.status, body: detail.slice(0, 2000) },
        };
      }

      const body = await response.json();
      const text = (body?.candidates?.[0]?.content?.parts ?? [])
        .map((part: { text?: string }) => part.text ?? "")
        .join("\n");

      return { ...parseVerdict(text), model, raw: body };
    },
  };
}

// --- Absence de fournisseur -------------------------------------------------

/**
 * Aucune clé configurée.
 *
 * On ne fabrique pas de verdict : chaque preuve part en revue humaine. C'est
 * coûteux et c'est voulu — inventer un « validé » ou un « rejeté » faute de
 * modèle serait la pire chose que ce code puisse faire.
 */
export function unavailableProvider(): VisionProvider {
  return {
    name: "unavailable",
    verdict(): Promise<VisionAnswer> {
      return Promise.resolve({
        ...unavailableVerdict("aucune cle de modele configuree"),
        model: "none",
        raw: null,
      });
    },
  };
}

/**
 * Claude s'il est configuré, Gemini sinon, revue humaine à défaut.
 *
 * L'ordre n'est pas négociable : la présence d'une clé de test ne doit jamais
 * détourner la production de Claude.
 */
export function selectProvider(env: (key: string) => string | undefined): VisionProvider {
  const anthropicKey = env("ANTHROPIC_API_KEY");
  if (anthropicKey) return anthropicProvider(anthropicKey);

  const geminiKey = env("GEMINI_API_KEY");
  if (geminiKey) return geminiProvider(geminiKey, env("GEMINI_MODEL") ?? undefined);

  return unavailableProvider();
}
