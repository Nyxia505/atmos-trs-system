/// Merges query parameters from the page URL and from hash routes
/// (e.g. `https://host/#/landing?type=lgu&municipality_id=oroquieta`
/// or path `https://host/checkin?type=spot&spot_id=…`).
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
  return Uri.base.toString();
}
