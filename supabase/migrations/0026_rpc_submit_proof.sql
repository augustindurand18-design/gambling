-- 0026 — RPC de soumission de preuve
--
-- Le client n'a aucune voie legale vers `proof_submitted` : la policy
-- `goals_update_draft` (0016) ne laisse ecrire que les brouillons, et
-- `transition_goal` (0020) est reservee au service role. Deposer une preuve
-- exige donc une fonction dediee.
--
-- Une RPC plutot qu'un trigger `after insert on proofs`, pour cinq raisons :
--
--   1. le trigger devrait de toute facon etre `security definer`, sans quoi
--      son UPDATE sur `goals` tomberait sur `goals_update_draft` — l'argument
--      « c'est plus simple » disparait ;
--   2. il ne peut pas refuser une preuve hors delai : la policy RLS ne connait
--      que l'etat, jamais `proof_deadline_at`. La preuve serait inseree, puis
--      l'objectif transitionne, alors que la fenetre est fermee ;
--   3. il ne verrouille pas l'objectif, laissant ouverte la course avec le
--      cron de cloture, qui peut rejeter a la meme seconde ;
--   4. il se declencherait aussi sur les inserts du service role (revue
--      humaine, reprises, fixtures de test) et provoquerait des transitions
--      surprises ;
--   5. il ne peut ni nommer un acteur ni porter une raison d'audit
--      intelligible, et rend le rejeu impossible.
--
-- Meme forme que `commit_goal` (0017), qui rend deja atomique l'engagement.

-- Delai laisse a l'utilisateur pour envoyer sa preuve apres l'ouverture de la
-- fenetre. Constante de reference de la base : `close-expired` et le cron
-- d'ouverture la lisent ici plutot que de reecrire 900 chacun.
--
-- Elle doit rester egale a MAX_CAPTURE_DELAY_SEC de
-- supabase/functions/_shared/anticheat.ts et a ProofWindow.duration cote iOS.
-- Un test de chaque cote assene le litteral pour rattraper une derive.
create or replace function app.proof_window_seconds()
returns int
language sql
immutable
set search_path = public, app
as $$
  select 900;
$$;

comment on function app.proof_window_seconds is
  'Delai de soumission d''une preuve, en secondes. Doit rester aligne sur MAX_CAPTURE_DELAY_SEC (anticheat.ts) et ProofWindow.duration (iOS).';

-- Tolerance d'horloge accordee au-dela de l'echeance.
--
-- Reprend CLOCK_SKEW_TOLERANCE_SEC de anticheat.ts. Refuser a la seconde pres
-- rejetterait des preuves que le controle anti-triche juge parfaitement
-- legitimes : photo prise a t+14:50, envoyee a t+15:05, horloge de l'appareil
-- decalee de quelques secondes. Trancher contre l'utilisateur sur un doute
-- d'horloge, c'est l'invariant 2 a l'envers.
create or replace function app.proof_clock_grace_seconds()
returns int
language sql
immutable
set search_path = public, app
as $$
  select 120;
$$;

comment on function app.proof_clock_grace_seconds is
  'Tolerance d''horloge au-dela de proof_deadline_at. Alignee sur CLOCK_SKEW_TOLERANCE_SEC (anticheat.ts).';


create or replace function public.submit_proof(
  p_goal_id uuid,
  p_storage_path text,
  p_image_sha256 text,
  p_image_bytes int default null,
  p_captured_at timestamptz default null,
  p_device_lat double precision default null,
  p_device_lng double precision default null,
  p_ondevice_precheck jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  -- L'identite vient d'auth.uid() et de nulle part ailleurs. Une fonction
  -- `security definer` qui accepterait un identifiant en parametre offrirait
  -- l'usurpation a qui sait appeler une RPC.
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
  -- l'application de retenter avec la meme image. On rend la preuve deja
  -- enregistree plutot que d'en creer une seconde ou d'echouer.
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

  -- La policy de storage (0018) impose deja ce prefixe a l'upload ; on refuse
  -- ici d'enregistrer un chemin qui pointerait ailleurs. Sans ce controle, une
  -- ligne de `proofs` pourrait designer le fichier de quelqu'un d'autre.
  if p_storage_path is null
     or p_storage_path not like (v_user_id::text || '/' || p_goal_id::text || '/%')
  then
    raise exception 'Chemin de stockage invalide : attendu %/%/...',
      v_user_id, p_goal_id
      using errcode = 'check_violation';
  end if;

  insert into public.proofs
    (goal_id, user_id, storage_path, image_sha256, image_bytes,
     captured_at, device_lat, device_lng, ondevice_precheck)
  values
    (p_goal_id, v_user_id, p_storage_path, p_image_sha256, p_image_bytes,
     p_captured_at, p_device_lat, p_device_lng, coalesce(p_ondevice_precheck, '{}'::jsonb))
  returning id into v_proof_id;

  perform set_config('app.actor', 'user', true);
  perform set_config('app.transition_reason', 'preuve soumise', true);

  -- La legalite de la transition reste verifiee par le trigger de 0015 :
  -- cette fonction ne fait qu'ouvrir une voie, elle n'ouvre pas une derogation.
  update public.goals
  set state = 'proof_submitted'
  where id = p_goal_id;

  return v_proof_id;
end;
$$;

-- Revocation nominative, lecon de 0020 : les privileges par defaut de Supabase
-- sont accordes nommement a `anon` et `authenticated`, et un revoke sur
-- `public` ne les entame pas.
revoke all on function public.submit_proof(
  uuid, text, text, int, timestamptz, double precision, double precision, jsonb
) from public;
revoke all on function public.submit_proof(
  uuid, text, text, int, timestamptz, double precision, double precision, jsonb
) from anon;

grant execute on function public.submit_proof(
  uuid, text, text, int, timestamptz, double precision, double precision, jsonb
) to authenticated;

comment on function public.submit_proof is
  'Enregistre une preuve et fait passer l''objectif en proof_submitted, atomiquement. Seule voie cliente vers cet etat : un UPDATE direct est interdit par la RLS.';
