-- 0016 — Row Level Security
--
-- Principe : l'utilisateur LIT ce qui le concerne, et n'ECRIT que ce qui
-- releve de sa volonte (creer un brouillon, l'engager, soumettre une preuve,
-- contester). Tout ce qui touche a l'argent et aux verdicts est ecrit
-- exclusivement par le service role depuis les Edge Functions.

alter table public.profiles              enable row level security;
alter table public.charities             enable row level security;
alter table public.goals                 enable row level security;
alter table public.stakes                enable row level security;
alter table public.consents              enable row level security;
alter table public.proofs                enable row level security;
alter table public.charges               enable row level security;
alter table public.disputes              enable row level security;
alter table public.devices               enable row level security;
alter table public.notification_schedule enable row level security;
alter table public.goal_state_transitions enable row level security;
alter table public.assiduity_weeks       enable row level security;
alter table public.stripe_events         enable row level security;

-- ---------------------------------------------------------------- profiles
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (user_id = (select auth.uid()));

-- L'utilisateur ne peut modifier que son affichage. Les plafonds, le blocage,
-- le solde du et l'etat d'abonnement sont pilotes par le serveur : la colonne
-- est protegee par un trigger dedie ci-dessous.
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function app.protect_profile_columns()
returns trigger
language plpgsql
as $$
begin
  -- La protection ne vise que les appels clients. Les Edge Functions
  -- (service_role), les migrations et l'administration passent librement.
  -- On teste le role effectif plutot que les claims JWT : une session psql
  -- d'administration peut porter des claims residuels sans etre un client.
  if current_role not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.stripe_customer_id       is distinct from old.stripe_customer_id
     or new.default_payment_method_id is distinct from old.default_payment_method_id
     or new.pm_last4              is distinct from old.pm_last4
     or new.pm_brand              is distinct from old.pm_brand
     or new.per_goal_cap_cents    is distinct from old.per_goal_cap_cents
     or new.monthly_cap_cents     is distinct from old.monthly_cap_cents
     or new.stake_block_active    is distinct from old.stake_block_active
     or new.outstanding_balance_cents is distinct from old.outstanding_balance_cents
     or new.subscription_tier     is distinct from old.subscription_tier
     or new.assiduity_discount_active is distinct from old.assiduity_discount_active
  then
    raise exception
      'Ces champs de profil sont pilotes par le serveur et ne peuvent pas etre modifies depuis le client'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

create trigger profiles_protect_columns
  before update on public.profiles
  for each row execute function app.protect_profile_columns();

-- --------------------------------------------------------------- charities
create policy charities_select_active on public.charities
  for select to authenticated
  using (active = true);

-- ------------------------------------------------------------------- goals
create policy goals_select_own on public.goals
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Creation d'un brouillon uniquement, et seulement si l'utilisateur n'est pas
-- bloque pour incident de paiement.
create policy goals_insert_draft on public.goals
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and state = 'draft'
    and not exists (
      select 1 from public.profiles p
      where p.user_id = (select auth.uid())
        and p.stake_block_active = true
    )
  );

-- Modification limitee aux brouillons. Le passage draft -> committed se fait
-- par une RPC dediee (commit_goal), pas par un UPDATE direct.
create policy goals_update_draft on public.goals
  for update to authenticated
  using (user_id = (select auth.uid()) and state = 'draft')
  with check (user_id = (select auth.uid()) and state = 'draft');

create policy goals_delete_draft on public.goals
  for delete to authenticated
  using (user_id = (select auth.uid()) and state = 'draft');

-- ------------------------------------------------------------------ stakes
create policy stakes_select_own on public.stakes
  for select to authenticated
  using (user_id = (select auth.uid()));
-- Aucune ecriture cliente : les mises sont creees par la RPC commit_goal.

-- ---------------------------------------------------------------- consents
create policy consents_select_own on public.consents
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy consents_insert_own on public.consents
  for insert to authenticated
  with check (user_id = (select auth.uid()));
-- Pas de policy update/delete : la table est append-only (triggers 0007).

-- ------------------------------------------------------------------ proofs
create policy proofs_select_own on public.proofs
  for select to authenticated
  using (user_id = (select auth.uid()));

-- L'utilisateur depose sa preuve uniquement si la fenetre est ouverte.
create policy proofs_insert_own on public.proofs
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.goals g
      where g.id = goal_id
        and g.user_id = (select auth.uid())
        and g.state = 'proof_window_open'
    )
  );
-- Les verdicts sont ecrits exclusivement par le service role.

-- ----------------------------------------------------------------- charges
create policy charges_select_own on public.charges
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------- disputes
create policy disputes_select_own on public.disputes
  for select to authenticated
  using (user_id = (select auth.uid()));
-- L'ouverture d'une contestation passe par l'Edge Function dispute-intake,
-- qui verifie l'etat et la fenetre. Pas d'insert direct.

-- ----------------------------------------------------------------- devices
create policy devices_select_own on public.devices
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy devices_insert_own on public.devices
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy devices_update_own on public.devices
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- --------------------------------------------------- notification_schedule
-- Volontairement AUCUNE policy de lecture : l'instant de declenchement doit
-- rester inconnu du client, sinon la fenetre surprise perd tout son sens.

-- --------------------------------------------------- goal_state_transitions
create policy transitions_select_own on public.goal_state_transitions
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------- assiduity_weeks
create policy assiduity_select_own on public.assiduity_weeks
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ------------------------------------------------------------ stripe_events
-- Aucune policy : reserve au service role.
