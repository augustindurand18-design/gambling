/**
 * Accès base pour les Edge Functions, en service role.
 *
 * Le service role contourne la RLS mais PAS les triggers : la machine à
 * états et l'immutabilité des consentements s'appliquent aussi ici. C'est
 * volontaire — une erreur de code ne doit pas pouvoir débiter quelqu'un.
 */

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!url || !key) {
    throw new Error(
      "SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont requis dans l'environnement de la fonction",
    );
  }

  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Client agissant au nom de l'utilisateur appelant, RLS comprise.
 * À utiliser dès qu'une fonction n'a pas besoin de privilèges élevés.
 */
export function userClient(authHeader: string): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");

  if (!url || !key) {
    throw new Error("SUPABASE_URL et SUPABASE_ANON_KEY sont requis");
  }

  return createClient(url, key, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Change l'état d'un objectif en attribuant la transition à un acteur.
 *
 * L'acteur est enregistré dans le journal d'audit et sert à retracer qui a
 * décidé quoi en cas de litige — un utilisateur peut contester un débit des
 * mois plus tard.
 */
export async function transitionGoal(
  db: SupabaseClient,
  params: {
    goalId: string;
    toState: string;
    actor: string;
    reason: string;
    fields?: Record<string, unknown>;
  },
): Promise<void> {
  const { error } = await db.rpc("transition_goal", {
    p_goal_id: params.goalId,
    p_to_state: params.toState,
    p_actor: params.actor,
    p_reason: params.reason,
    p_fields: params.fields ?? {},
  });

  if (error) {
    throw new Error(
      `Transition ${params.toState} impossible pour l'objectif ${params.goalId} : ${error.message}`,
    );
  }
}

/** Réponse JSON uniforme. */
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function errorResponse(message: string, status = 400): Response {
  return json({ error: message }, status);
}

/**
 * Vérifie qu'un appel provient bien d'un utilisateur authentifié.
 * Retourne son identifiant, ou null.
 */
export async function requireUser(req: Request): Promise<
  { userId: string; authHeader: string } | null
> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;

  const { data, error } = await userClient(authHeader).auth.getUser();
  if (error || !data.user) return null;

  return { userId: data.user.id, authHeader };
}
