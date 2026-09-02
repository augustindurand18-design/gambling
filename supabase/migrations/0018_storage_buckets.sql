-- 0018 — Stockage des preuves
--
-- Bucket prive. Aucune URL publique : les Edge Functions lisent via le service
-- role, l'app via des URL signees a duree courte. Chemin impose :
--   proofs/{user_id}/{goal_id}/{uuid}.jpg

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'proofs',
  'proofs',
  false,
  10 * 1024 * 1024,                       -- 10 Mo
  array['image/jpeg', 'image/heic', 'image/png']
)
on conflict (id) do nothing;

-- L'utilisateur depose uniquement dans son propre dossier.
create policy proofs_insert_own_folder on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'proofs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy proofs_select_own_folder on storage.objects
  for select to authenticated
  using (
    bucket_id = 'proofs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Pas d'update ni de delete cote client : une preuve deposee est definitive.
-- La purge (retention RGPD) est faite par la fonction purge-proofs.
