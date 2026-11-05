-- LGU event photos on the existing public `tourist-images` bucket.
-- Path: events/{eventId}/photo_{time}.ext
-- Run in Supabase Dashboard → SQL Editor.
--
-- The Flutter app uploads with the anon key (Firebase Auth is separate),
-- the same way tourist-spot and establishment photos already do.
-- Public read is the bucket's public flag. Insert, update, and delete
-- are limited to the events/ folder. Do not use the service_role key
-- in the app.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'tourist-images',
  'tourist-images',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = true,
    file_size_limit = 10485760;

drop policy if exists "lgu_event_images_insert" on storage.objects;
drop policy if exists "lgu_event_images_update" on storage.objects;
drop policy if exists "lgu_event_images_delete" on storage.objects;

create policy "lgu_event_images_insert"
on storage.objects for insert
to anon, authenticated
with check (
  bucket_id = 'tourist-images'
  and (storage.foldername(name))[1] = 'events'
);

create policy "lgu_event_images_update"
on storage.objects for update
to anon, authenticated
using (
  bucket_id = 'tourist-images'
  and (storage.foldername(name))[1] = 'events'
)
with check (
  bucket_id = 'tourist-images'
  and (storage.foldername(name))[1] = 'events'
);

create policy "lgu_event_images_delete"
on storage.objects for delete
to anon, authenticated
using (
  bucket_id = 'tourist-images'
  and (storage.foldername(name))[1] = 'events'
);
