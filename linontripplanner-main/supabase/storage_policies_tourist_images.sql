-- TripPlan / ATMoS: Supabase Storage policies for `tourist-images`
--
-- Run this in Supabase Dashboard → SQL Editor → New query → Run.
-- Fixes: "new row violates row-level security policy" on admin image upload.
--
-- The Flutter app uploads with the anon key (Firebase Auth is separate),
-- so INSERT/UPDATE must be allowed for `anon` on this bucket.

-- Ensure the bucket exists and is public (Dashboard → Storage also works).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'tourist-images',
  'tourist-images',
  true,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE
SET public = true;

-- Drop older conflicting policies if re-running this script.
DROP POLICY IF EXISTS "tourist_images_anon_select" ON storage.objects;
DROP POLICY IF EXISTS "tourist_images_anon_insert" ON storage.objects;
DROP POLICY IF EXISTS "tourist_images_anon_update" ON storage.objects;
DROP POLICY IF EXISTS "tourist_images_anon_delete" ON storage.objects;
DROP POLICY IF EXISTS "tourist_images_public_select" ON storage.objects;

-- Public read (needed for listing / probing; public URLs also work when bucket is public).
CREATE POLICY "tourist_images_anon_select"
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (bucket_id = 'tourist-images');

-- Admin app uploads (events, announcements, spots, municipalities, profiles).
CREATE POLICY "tourist_images_anon_insert"
ON storage.objects
FOR INSERT
TO anon, authenticated
WITH CHECK (
  bucket_id = 'tourist-images'
  AND (
    (storage.foldername(name))[1] IN (
      'events',
      'announcements',
      'municipalities',
      'tourist-spots',
      'images',
      'uploads',
      'user_profiles',
      'user-profiles'
    )
    OR name NOT LIKE '%/%'
  )
);

-- Allow overwrite (x-upsert: true).
CREATE POLICY "tourist_images_anon_update"
ON storage.objects
FOR UPDATE
TO anon, authenticated
USING (bucket_id = 'tourist-images')
WITH CHECK (bucket_id = 'tourist-images');

-- Optional: allow removing a replaced object from the app later.
CREATE POLICY "tourist_images_anon_delete"
ON storage.objects
FOR DELETE
TO anon, authenticated
USING (
  bucket_id = 'tourist-images'
  AND (storage.foldername(name))[1] IN (
    'events',
    'announcements',
    'municipalities',
    'tourist-spots',
    'images',
    'uploads',
    'user_profiles',
    'user-profiles'
  )
);
