/// Public Supabase Storage config for remote tourist images.
///
/// Object keys mirror paths under `assets/` (without the `assets/` prefix),
/// e.g. `assets/images/foo.jpg` → `images/foo.jpg`.
abstract final class SupabaseStorageConfig {
  static const String projectUrl =
      'https://cgpjqkbbmyxvitwpkikn.supabase.co';
  static const String bucket = 'tourist-images';

  /// When true, bundled `assets/...` tourist images resolve to Supabase public URLs.
  static const bool useRemoteImages = true;

  static String get publicBase =>
      '$projectUrl/storage/v1/object/public/$bucket';

  /// Logos / branding stay bundled for splash, auth, and offline chrome.
  static bool keepLocalAsset(String path) {
    final p = path.replaceAll('\\', '/').toLowerCase();
    if (!p.startsWith('assets/')) return true;
    if (p.contains('final logo')) return true;
    if (p.contains('atmos_trs_brand_logo')) return true;
    if (p.contains('atmostrs logo')) return true;
    if (p.contains('tourism logo')) return true;
    if (p.endsWith('/logo.png') || p.endsWith('/logo.jpg')) return true;
    if (p.contains('asenso_misamis_occidental_circular_logo')) return true;
    if (p.contains('asenso_misamis_occidental_wordmark')) return true;
    if (p.contains('misamis_occidental_official_seal')) return true;
    if (p.contains('login_hero_bg')) return true;
    if (p.contains('landing page.png')) return true;
    if (p.contains('onboarding_screen/')) return true;
    if (p.contains('vr_tour/')) return true;
    if (p.endsWith('.mp4') || p.endsWith('.webm') || p.endsWith('.ttf')) {
      return true;
    }
    return false;
  }

  /// `assets/images/x.jpg` → `images/x.jpg`
  static String? objectKeyFromAssetPath(String assetPath) {
    var p = assetPath.trim().replaceAll('\\', '/');
    if (p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return null;
    while (p.contains('%')) {
      try {
        final decoded = Uri.decodeComponent(p);
        if (decoded == p) break;
        p = decoded;
      } catch (_) {
        break;
      }
    }
    if (p.startsWith('assets/')) {
      p = p.substring('assets/'.length);
    }
    if (p.isEmpty) return null;
    return sanitizeObjectKey(p);
  }

  /// Supabase rejects some Unicode punctuation/accents in object keys.
  static String sanitizeObjectKey(String key) {
    final out = StringBuffer();
    for (final rune in key.runes) {
      if (rune == 0x2013 || rune == 0x2014 || rune == 0x2022) {
        out.write('-');
      } else if (rune == 0x00E9 || rune == 0x00E8 || rune == 0x00EA) {
        out.write('e');
      } else if (rune == 0x00C9 || rune == 0x00C8 || rune == 0x00CA) {
        out.write('E');
      } else if (rune == 0x00E0 || rune == 0x00E1) {
        out.write('a');
      } else if (rune == 0x00F1) {
        out.write('n');
      } else if (rune == 0x00FC) {
        out.write('u');
      } else if (rune <= 127) {
        out.writeCharCode(rune);
      } else {
        out.write('x');
      }
    }
    return out.toString();
  }

  static String publicUrlForObjectKey(String objectKey) {
    final encoded = sanitizeObjectKey(objectKey)
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return '$publicBase/$encoded';
  }

  /// Convert an asset path (or pass-through http/data) to the display URL.
  static String resolve(String pathOrUrl) {
    final raw = pathOrUrl.trim();
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('data:image')) {
      return raw;
    }
    if (!useRemoteImages || keepLocalAsset(raw)) return raw;

    final key = objectKeyFromAssetPath(raw);
    if (key == null) return raw;
    return publicUrlForObjectKey(key);
  }

  /// If [url] is a Supabase public object URL for our bucket, return local asset path.
  static String? assetPathFromPublicUrl(String url) {
    final u = url.trim();
    final prefix = '$publicBase/';
    if (!u.startsWith(prefix)) return null;
    final encodedKey = u.substring(prefix.length);
    try {
      final key = encodedKey
          .split('/')
          .map(Uri.decodeComponent)
          .join('/');
      return 'assets/$key';
    } catch (_) {
      return 'assets/${Uri.decodeFull(encodedKey)}';
    }
  }
}
