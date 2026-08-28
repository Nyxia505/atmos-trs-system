/// Merges query parameters from the page URL and from hash routes
/// (e.g. `https://host/#/landing?type=lgu&municipality_id=oroquieta`).
Map<String, String> mergedLaunchQueryParameters(Uri uri) {
  final out = Map<String, String>.from(uri.queryParameters);
  final fragment = uri.fragment.trim();
  if (fragment.isEmpty) return out;

  final qIndex = fragment.indexOf('?');
  if (qIndex < 0) return out;

  final fragmentQuery = fragment.substring(qIndex + 1);
  if (fragmentQuery.isEmpty) return out;

  out.addAll(Uri.splitQueryString(fragmentQuery));
  return out;
}

/// Full launch URL string for QR parsing on web (includes fragment query).
String launchUrlStringForQrParsing() {
  final base = Uri.base;
  if (base.fragment.contains('?')) {
    return base.toString();
  }
  return base.toString();
}
