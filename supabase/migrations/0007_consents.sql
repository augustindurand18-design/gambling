-- 0007 — Consentements (append-only, immuables)
--
-- Piece maitresse juridique : prouve ce que l'utilisateur a vu et accepte,
-- au moment ou il l'a accepte. Aucune modification n'est possible, meme par
-- le service role. Une correction = une nouvelle ligne.

create table public.consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,

  consent_type consent_type not null,
  goal_id uuid references public.goals(id) on delete set null,
  stake_id uuid references public.stakes(id) on delete set null,

  -- Version des CGU/CGV en vigueur au moment de l'acceptation
  terms_version text not null,
  -- SHA-256 du texte legal exactement tel qu'affiche a l'ecran
  terms_hash text not null check (terms_hash ~ '^[0-9a-f]{64}$'),

  -- Snapshot complet : montant, devise, association + bps + split calcule,
  -- deadline, mode de verification, fenetre, pm_last4/brand, plafonds acceptes,
  -- phrase legale affichee, app_version, plateforme.
  payload jsonb not null,

  ip inet,
  user_agent text,
  app_version text,
  platform text,

  -- Chainage d'integrite : hash de la ligne precedente du meme utilisateur.
  prev_hash text,
  row_hash text,

  accepted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  -- Un consentement de mise doit referencer l'objectif et la mise
  constraint consents_stake_refs check (
    consent_type <> 'stake_commitment'
    or (goal_id is not null and stake_id is not null)
  )
);

create index consents_user_idx on public.consents (user_id, accepted_at desc);
create index consents_goal_idx on public.consents (goal_id);

-- Immutabilite absolue : bloque UPDATE et DELETE pour tout le monde,
-- service role compris. Un trigger l'emporte sur les droits de role.
create or replace function app.forbid_consent_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'consents est une table append-only : % interdit (id=%)',
    tg_op, coalesce(old.id::text, 'n/a')
    using errcode = 'raise_exception';
end;
$$;

create trigger consents_no_update
  before update on public.consents
  for each row execute function app.forbid_consent_mutation();

create trigger consents_no_delete
  before delete on public.consents
  for each row execute function app.forbid_consent_mutation();

-- Calcule le chainage de hash a l'insertion (tamper-evidence).
create or replace function app.chain_consent_hash()
returns trigger
language plpgsql
as $$
declare
  v_prev text;
begin
  select row_hash into v_prev
  from public.consents
  where user_id = new.user_id
  order by accepted_at desc, id desc
  limit 1;

  new.prev_hash := v_prev;
  new.row_hash := encode(
    extensions.digest(
      coalesce(v_prev, '') ||
      new.user_id::text ||
      new.consent_type::text ||
      new.terms_hash ||
      new.payload::text ||
      new.accepted_at::text,
      'sha256'
    ),
    'hex'
  );
  return new;
end;
$$;

create trigger consents_chain_hash
  before insert on public.consents
  for each row execute function app.chain_consent_hash();
