-- 0028 — La preuve transporte son EXIF
--
-- `submit_proof` (0026) n'avait pas de quoi recevoir l'EXIF, et l'application
-- n'en envoyait pas. `proofs.exif` restait donc toujours nul.
--
-- Ce n'etait pas un simple champ manquant. `runAntiCheat` leve `exif_missing`
-- des que l'EXIF est absent — a raison : une photo prise par un appareil en
-- produit toujours, et son absence suggere une image fabriquee. Or
-- `routeVerdict` envoie en revue humaine toute preuve portant le moindre
-- signal. Consequence : **100 % des preuves partaient en revue humaine**,
-- alors que l'architecture vise 85 % absorbes par l'IA et qu'un controle
-- humain coute 0,20 a 0,50 €. La verification automatique ne servait a rien.
--
-- Constate en faisant tourner verify-proof contre une vraie preuve, pas en
-- relisant le code : chaque piece etait correcte isolement.
--
-- L'EXIF reste une donnee declaree par l'appareil, donc non fiable — c'est
-- `server_received_at` qui fait foi. Il sert a reperer une incoherence, pas a
-- etablir une verite.
--
-- Minimisation RGPD : l'application n'envoie qu'une liste blanche de champs.
-- L'EXIF brut d'une photo contient les coordonnees GPS de l'endroit ou elle a
-- ete prise, dont nous n'avons pas besoin ici.

-- La signature change : l'ancienne est retiree plutot que surchargee, sinon
-- les deux coexisteraient et un appel sans EXIF resterait ambigu.
drop function if exists public.submit_proof(
  uuid, text, text, int, timestamptz, double precision, double precision, jsonb
);

create or replace function public.submit_proof(
  p_goal_id uuid,
  p_storage_path text,
  p_image_sha256 text,
  p_image_bytes int default null,
  p_captured_at timestamptz default null,
  p_device_lat double precision default null,
  p_device_lng double precision default null,
  p_ondevice_precheck jsonb default '{}'::jsonb,
  p_exif jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_user_id uuid := auth.uid();
  v_goal public.goals%rowtype;
  v_proof_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentification requise pour deposer une preuve'
      using errcode = 'insufficient_privilege';
  end if;

  -- Le verrou est pris AVANT toute verification. Sans lui,
  -- app.close_expired_goals peut rejeter l'objectif entre le controle de
  -- l'echeance et l'insertion : l'utilisateur se retrouverait avec une preuve
  -- rattachee a un objectif deja perdu.
  select * into v_goal
  from public.goals
  where id = p_goal_id and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Objectif % introuvable', p_goal_id
      using errcode = 'no_data_found';
  end if;

  -- Rejouable : une coupure reseau apres l'insertion ne doit pas empecher
  -- l'application de retenter avec la meme image.
  if v_goal.state = 'proof_submitted' then
    select id into v_proof_id
    from public.proofs
    where goal_id = p_goal_id and image_sha256 = p_image_sha256
    order by created_at desc
    limit 1;

    if v_proof_id is not null then
      return v_proof_id;
    end if;
  end if;

  if v_goal.state <> 'proof_window_open' then
    raise exception 'La fenetre de preuve n''est pas ouverte pour cet objectif (etat : %)',
      v_goal.state
      using errcode = 'check_violation';
  end if;

  if v_goal.proof_deadline_at is null
     or now() > v_goal.proof_deadline_at
                + make_interval(secs => app.proof_clock_grace_seconds())
  then
    raise exception 'Le delai de soumission est ecoule'
      using errcode = 'check_violation';
  end if;

  if p_storage_path is null
     or p_storage_path not like (v_user_id::text || '/' || p_goal_id::text || '/%')
  then
    raise exception 'Chemin de stockage invalide : attendu %/%/...',
      v_user_id, p_goal_id
      using errcode = 'check_violation';
  end if;

  insert into public.proofs
    (goal_id, user_id, storage_path, image_sha256, image_bytes,
     captured_at, device_lat, device_lng, ondevice_precheck, exif)
  values
    (p_goal_id, v_user_id, p_storage_path, p_image_sha256, p_image_bytes,
     p_captured_at, p_device_lat, p_device_lng,
     coalesce(p_ondevice_precheck, '{}'::jsonb), p_exif)
  returning id into v_proof_id;

  perform set_config('app.actor', 'user', true);
  perform set_config('app.transition_reason', 'preuve soumise', true);

  update public.goals
  set state = 'proof_submitted'
  where id = p_goal_id;

  return v_proof_id;
end;
$$;

revoke all on function public.submit_proof(
  uuid, text, text, int, timestamptz, double precision, double precision, jsonb, jsonb
) from public;
revoke all on function public.submit_proof(
  uuid, text, text, int, timestamptz, double precision, double precision, jsonb, jsonb
) from anon;

grant execute on function public.submit_proof(
  uuid, text, text, int, timestamptz, double precision, double precision, jsonb, jsonb
) to authenticated;

comment on function public.submit_proof is
  'Enregistre une preuve et fait passer l''objectif en proof_submitted, atomiquement. Seule voie cliente vers cet etat. L''EXIF recu est declare par l''appareil, donc indicatif : server_received_at fait foi.';
