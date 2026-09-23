-- Optional: allow AE gallery uploads with SUPABASE_ANON_KEY (preferred over service role).
-- Run in Supabase Dashboard → SQL Editor.
-- Bucket: tourist-images  Path: establishments/{firebaseUid}/…

drop policy if exists "ae_gallery_insert" on storage.objects;
drop policy if exists "ae_gallery_update" on storage.objects;
drop policy if exists "ae_gallery_delete" on storage.objects;

create policy "ae_gallery_insert"
on storage.objects for insert
to anon, authenticated
with check (
  bucket_id = 'tourist-images'
  and (storage.foldername(name))[1] = 'establishments'
);

create policy "ae_gallery_update"
on storage.objects for update
to anon, authenticated
using (
  bucket_id = 'tourist-images'
  and (storage.foldername(name))[1] = 'establishments'
);

create policy "ae_gallery_delete"
on storage.objects for delete
to anon, authenticated
using (
  bucket_id = 'tourist-images'
  and (storage.foldername(name))[1] = 'establishments'
);
