-- La verification part a la soumission, sans attendre le battement.
--
-- `verify-proof` n'etait reveillee que par le cron, a la minute pleine : une
-- preuve envoyee a 26'05 attendait 27'00 avant que le modele ne commence.
-- Cinquante-cinq secondes d'ecran d'attente pour quelqu'un qui vient de
-- photographier son lit, alors que le verdict prend quelques secondes.
--
-- L'insertion de la preuve reveille donc la fonction elle-meme. `net.http_post`
-- ne bloque pas — il depose la requete dans une file et rend la main — donc
-- `submit_proof` repond a l'application aussi vite qu'avant.
--
-- Le cron reste le filet : si cet appel echoue, la preuve sera reprise au tour
-- suivant. C'est pour cela que l'echec est avale ici. Une preuve qui n'a pas
-- pu etre annoncee ne doit surtout pas faire echouer sa propre soumission :
-- l'utilisateur perdrait sa fenetre, et donc sa mise, pour une panne qui ne
-- lui appartient pas.

create or replace function app.verify_on_proof_insert()
returns trigger
language plpgsql
security definer
set search_path = public, app, extensions
as $$
begin
  begin
    perform app.trigger_pending_verifications();
  exception when others then
    null;
  end;

  return new;
end;
$$;

comment on function app.verify_on_proof_insert is
  'Reveille verify-proof des l''arrivee d''une preuve. Sans effet sur la soumission.';

drop trigger if exists proofs_verify_now on public.proofs;

create trigger proofs_verify_now
  after insert on public.proofs
  for each row
  execute function app.verify_on_proof_insert();
