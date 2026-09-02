/**
 * Construction des prompts de vérification.
 *
 * Le modèle est arbitre d'un enjeu financier réel. Le prompt est donc écrit
 * pour être conservateur : dans le doute, il répond `uncertain`, ce qui route
 * vers une revue humaine. Il ne doit jamais chercher à « trancher » pour
 * éviter l'indécision — un faux rejet coûte de l'argent à l'utilisateur et
 * détruit la confiance dans le produit.
 */

export type Verdict = "pass" | "fail" | "uncertain";

export interface VerdictResponse {
  verdict: Verdict;
  confidence: number;
  reason: string;
  spoof_suspected: boolean;
}

export interface PromptContext {
  goalTitle: string;
  proofInstruction: string | null;
  goalType: string;
  /** Motifs de suspicion remontés par l'anti-triche serveur. */
  antiCheatFlags: string[];
  /** Instant d'ouverture de la fenêtre, en heure locale de l'utilisateur. */
  windowOpenedAtLocal: string | null;
  timezone: string;
}

const SYSTEM_PROMPT = `Tu vérifies des preuves photo pour une application où les utilisateurs
engagent de l'argent sur leurs objectifs personnels. Un rejet leur coûte
réellement de l'argent.

Ta règle de conduite :
- Tu ne valides que ce que tu vois. Tu n'imagines rien, tu ne complètes rien.
- Tu ne rejettes que si la photo contredit clairement l'objectif.
- Dans TOUS les autres cas — photo ambiguë, cadrage partiel, mauvaise
  lumière, élément attendu hors champ, doute quelconque — tu réponds
  "uncertain". Un humain prendra le relais. C'est le comportement attendu,
  pas un échec de ta part.

Détection de fraude. Signale spoof_suspected uniquement si tu observes des
indices matériels :
- photo d'un écran (moiré, pixels visibles, reflets, bordure d'appareil,
  luminosité uniforme d'une dalle) ;
- photo d'une impression ou d'une autre photo (grain papier, bords, ombre
  portée régulière) ;
- image manifestement générée ou retouchée (artefacts, incohérences
  d'éclairage ou de perspective).
Une photo simplement floue, sombre ou mal cadrée n'est PAS une fraude.

Tu réponds exclusivement par un objet JSON valide, sans texte autour :
{"verdict":"pass"|"fail"|"uncertain","confidence":0.0-1.0,"reason":"une phrase en français","spoof_suspected":true|false}

confidence exprime ta certitude sur le verdict rendu, pas la qualité de la photo.`;

export function buildSystemPrompt(): string {
  return SYSTEM_PROMPT;
}

export function buildUserPrompt(ctx: PromptContext): string {
  const parts: string[] = [];

  parts.push(`Objectif de l'utilisateur : « ${ctx.goalTitle} »`);

  if (ctx.proofInstruction) {
    parts.push(
      `Ce que la photo doit montrer, tel que l'utilisateur l'a défini au moment ` +
        `de s'engager : « ${ctx.proofInstruction} »`,
    );
  }

  if (ctx.windowOpenedAtLocal) {
    parts.push(
      `La preuve a été demandée à ${ctx.windowOpenedAtLocal} (heure locale, ${ctx.timezone}). ` +
        `La photo doit être cohérente avec ce moment de la journée — lumière, ` +
        `activité visible. Une incohérence flagrante est un signal, mais ne ` +
        `suffit pas à elle seule à rejeter.`,
    );
  }

  parts.push(typeGuidance(ctx.goalType));

  // Les signaux anti-triche sont fournis comme contexte, pas comme verdict.
  // C'est le serveur qui décide de leur portée, pas le modèle.
  if (ctx.antiCheatFlags.length > 0) {
    parts.push(
      `Signaux techniques relevés en amont : ${ctx.antiCheatFlags.join(", ")}. ` +
        `Tiens-en compte dans ton appréciation sans les considérer comme ` +
        `une preuve de fraude à eux seuls.`,
    );
  }

  parts.push(
    `Cette photo remplit-elle l'objectif ? Réponds par le seul objet JSON.`,
  );

  return parts.join("\n\n");
}

function typeGuidance(goalType: string): string {
  switch (goalType) {
    case "object_scene":
      return `Il s'agit de photographier une scène ou un objet réel à un instant donné. ` +
        `Vérifie que l'élément attendu est présent et que la scène est vraisemblable.`;

    case "presence":
      return `Il s'agit de prouver une présence sur un lieu. Vérifie que le lieu ` +
        `visible correspond à celui annoncé. La position GPS est vérifiée ` +
        `séparément : ne te prononce que sur ce que montre l'image.`;

    case "usage_data":
      return `Il s'agit d'une capture de données d'usage du téléphone. Lis les ` +
        `valeurs affichées et compare-les à l'objectif. Ici, une capture ` +
        `d'écran est le format attendu et ne constitue pas une fraude.`;

    case "action_export":
      return `Il s'agit d'un export provenant d'une autre application. Lis les ` +
        `valeurs affichées et compare-les à l'objectif. Une capture d'écran ` +
        `est le format attendu et ne constitue pas une fraude.`;

    default:
      return `Vérifie que la photo correspond à l'objectif annoncé.`;
  }
}

/**
 * Analyse la réponse du modèle.
 *
 * Toute réponse illisible devient `uncertain` : on ne débite jamais quelqu'un
 * sur une réponse qu'on n'a pas su lire.
 */
export function parseVerdict(raw: string): VerdictResponse {
  const fallback: VerdictResponse = {
    verdict: "uncertain",
    confidence: 0,
    reason: "Réponse du modèle illisible",
    spoof_suspected: false,
  };

  // Le modèle encadre parfois le JSON d'un bloc de code ou d'un préambule.
  const match = raw.match(/\{[\s\S]*\}/);
  if (!match) return fallback;

  let parsed: unknown;
  try {
    parsed = JSON.parse(match[0]);
  } catch {
    return fallback;
  }

  if (typeof parsed !== "object" || parsed === null) return fallback;
  const obj = parsed as Record<string, unknown>;

  const verdict = obj.verdict;
  if (verdict !== "pass" && verdict !== "fail" && verdict !== "uncertain") {
    return fallback;
  }

  const confidence = typeof obj.confidence === "number" &&
      Number.isFinite(obj.confidence)
    ? Math.min(1, Math.max(0, obj.confidence))
    : 0;

  return {
    verdict,
    confidence,
    reason: typeof obj.reason === "string" && obj.reason.trim()
      ? obj.reason.trim().slice(0, 500)
      : "Aucun motif fourni",
    spoof_suspected: obj.spoof_suspected === true,
  };
}
