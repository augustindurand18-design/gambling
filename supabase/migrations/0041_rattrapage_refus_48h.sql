-- Rattrapage des refus a qui `verify-proof` a pose 48 heures de recours.
--
-- `0036` a ramene `app.dispute_window_hours()` a zero, mais l'Edge Function
-- gardait la valeur en dur : chaque preuve refusee depuis repartait avec une
-- echeance a +48 h. Or `app.close_expired_goals()` ne clot un `rejected`
-- qu'une fois cette echeance passee — l'objectif restait donc deux jours sur
-- l'accueil, la mise ni liberee ni prelevee, et l'utilisateur sans aucun
-- geste possible.
--
-- La fonction est corrigee ; restent les objectifs deja marques. Meme geste
-- que `0036` : on ramene l'echeance a maintenant, le battement suivant les
-- clot en `closed_failed` et le cycle de debit reprend son cours.
update public.goals
set dispute_deadline_at = now()
where state = 'rejected'
  and dispute_deadline_at is not null
  and dispute_deadline_at > now();
