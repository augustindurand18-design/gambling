-- Retrait de la fenetre de contestation.
--
-- Une preuve refusee ouvrait 48 heures de recours avant que la mise ne soit
-- prelevee. Ce delai disparait : l'objectif est clos et le debit lance des le
-- verdict.
--
-- Ce que cela coute, et qui doit rester ecrit noir sur blanc : la
-- contestation etait le dernier recours humain avant un prelevement, et donc
-- la traduction concrete de l'invariant 2 — on ne debite jamais sur un doute.
-- Un faux negatif du modele debite desormais sans que personne ne puisse s'y
-- opposer. Decision produit du 2026-09-06, a reexaminer avant la beta,
-- d'autant que le seuil de revue humaine sur le montant a ete retire le meme
-- jour : les deux gardes sont tombees ensemble.
--
-- La fonction est conservee plutot que supprimee : remettre un delai ne
-- demandera qu'une valeur, et `close_expired_goals` continue de lire une
-- echeance non nulle. A zero heure, l'echeance vaut `now()` a la pose, et le
-- battement suivant clot l'objectif — une minute de latence au plus.
create or replace function app.dispute_window_hours()
returns int
language sql
immutable
set search_path = public, app
as $$
  select 0;
$$;

comment on function app.dispute_window_hours is
  'Duree du recours apres un refus. Zero : le debit suit le verdict (2026-09-06).';

-- Les objectifs deja refuses attendent une echeance posee sous l'ancienne
-- regle. On ne les y laisse pas : ils seraient les seuls a beneficier d'un
-- recours que plus rien n'offre, et resteraient en `rejected` deux jours de
-- plus sans que personne ne puisse en faire quoi que ce soit.
update public.goals
set dispute_deadline_at = now()
where state = 'rejected'
  and dispute_deadline_at is not null
  and dispute_deadline_at > now();
