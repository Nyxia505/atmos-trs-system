/// Supabase Storage settings for tourism catalog photos + Edge Function push.
///
/// Setup:
/// 1. Create a project at https://supabase.com
/// 2. Project Settings → API → copy Project URL and anon public key
/// 3. Storage → New bucket → name `tourist-images` → Public bucket ON
/// 4. SQL Editor → run `supabase/storage_policies_tourist_images.sql`
///    (required so admin image uploads are not blocked by RLS)
/// 5. Paste URL + anon key below, then hot-restart the app
/// 6. Push (Spark-safe, no Firebase Blaze):
///    - Firebase Console → Project settings → Service accounts → Generate key
///    - Set secret: FIREBASE_SERVICE_ACCOUNT_JSON = that JSON file contents
///    - Deploy: `npx supabase functions deploy notify-tourism-event --project-ref cgpjqkbbmyxvitwpkikn`
///
/// Firestore still stores only the public image URL in `imagePath` / `image_url`.
class SupabaseConfig {
  SupabaseConfig._();

  /// Example: https://abcdefgh.supabase.co
  static const String url = 'https://cgpjqkbbmyxvitwpkikn.supabase.co';

  /// Project Settings → API → publishable / anon key
  static const String anonKey =
      'sb_publishable_BIe5RFsrZ5hgRDNphZBTgQ_tu6ajEZf';

  /// Public Storage bucket for uploads + curated library (must match Supabase).
  /// Older docs referred to `tourism-images`; this project only has
  /// `tourist-images`.
  static const String imageBucket = 'tourist-images';

  /// Alias of [imageBucket] — curated municipality / tourist-spot photos.
  static const String photoLibraryBucket = imageBucket;

  /// Edge Function that sends FCM to topic `tourism_events`.
  static const String notifyTourismEventFunctionPath = 'notify-tourism-event';

  static bool get isConfigured =>
      url.isNotEmpty &&
      !url.contains('YOUR_PROJECT_REF') &&
      anonKey.isNotEmpty &&
      !anonKey.contains('YOUR_SUPABASE_ANON_KEY');

  static String get storageApiBase =>
      '${url.replaceAll(RegExp(r'/+$'), '')}/storage/v1';

  static String get functionsApiBase =>
      '${url.replaceAll(RegExp(r'/+$'), '')}/functions/v1';

  static String get notifyTourismEventFunctionUrl =>
      '$functionsApiBase/$notifyTourismEventFunctionPath';

  /// Public URL for [objectPath] in [bucket]. Each segment is percent-encoded so
  /// object names containing spaces, `&` or `'` still resolve.
  static String publicObjectUrl(String bucket, String objectPath) {
    final segments = objectPath
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return '$storageApiBase/object/public/$bucket/$segments';
  }

  /// True for a public URL served by this Supabase project's Storage.
  static bool isSupabaseStorageUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('.supabase.co/storage/') ||
        u.contains('/storage/v1/object/public/');
  }
}
