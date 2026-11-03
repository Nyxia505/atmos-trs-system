import 'package:flutter/material.dart';

import 'data.dart';

const kProvinceWideScope = 'province';
const kMunicipalityScope = 'municipality';
const kProvinceWideValue = '__province_wide__';
const kAddEventTypeValue = '__add_event_type__';
const kProvinceWideLabel =
    'All Cities/Municipalities – Misamis Occidental (Province-wide)';
const kProvinceWideDisplay = 'Province-wide – Misamis Occidental';

const Color kCatalogOrange = Color(0xFFFF6B00);

String normalizeCatalogEventType(String raw) {
  return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool eventTypeAlreadyExists(String raw, Iterable<String> existing) {
  final key = normalizeCatalogEventType(raw).toLowerCase();
  if (key.isEmpty) return false;
  return existing.any((item) => item.trim().toLowerCase() == key);
}

bool isProvinceWideTarget({
  String audienceScope = '',
  String municipality = '',
  String municipalityId = '',
}) {
  final scope = audienceScope.trim().toLowerCase();
  if (scope == kProvinceWideScope ||
      scope == 'province_wide' ||
      scope == kProvinceWideValue) {
    return true;
  }
  final id = municipalityId.trim().toLowerCase();
  if (id == 'province' ||
      id == 'misamis_occidental' ||
      id == kProvinceWideValue) {
    return true;
  }
  final name = municipality.trim().toLowerCase();
  return name == kProvinceWideValue ||
      name == kProvinceWideDisplay.toLowerCase() ||
      name == kProvinceWideLabel.toLowerCase() ||
      name.contains('province-wide') ||
      name.contains('province wide');
}

String catalogLocationLabel({
  required String municipality,
  String audienceScope = '',
  String municipalityId = '',
}) {
  if (isProvinceWideTarget(
    audienceScope: audienceScope,
    municipality: municipality,
    municipalityId: municipalityId,
  )) {
    return kProvinceWideDisplay;
  }
  return municipality.trim();
}

String catalogAudienceScopeForSelection(String? selected) {
  return selected == kProvinceWideValue
      ? kProvinceWideScope
      : kMunicipalityScope;
}

String catalogMunicipalityForSelection(String? selected) {
  if (selected == null || selected.trim().isEmpty) return '';
  if (selected == kProvinceWideValue) return kProvinceWideDisplay;
  return selected.trim();
}

String? catalogSelectionFromRecord({
  required String municipality,
  String audienceScope = '',
  String municipalityId = '',
}) {
  if (isProvinceWideTarget(
    audienceScope: audienceScope,
    municipality: municipality,
    municipalityId: municipalityId,
  )) {
    return kProvinceWideValue;
  }
  final name = municipality.trim();
  if (name.isEmpty) return null;
  return name;
}

InputDecoration catalogFieldDecoration({
  required String label,
  String? hint,
  bool optional = false,
}) {
  final suffix = optional ? ' (optional)' : '';
  return InputDecoration(
    labelText: '$label$suffix',
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    alignLabelWithHint: hint != null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kCatalogOrange, width: 1.75),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDC2626)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.75),
    ),
  );
}

List<DropdownMenuItem<String?>> catalogAudienceItems({String? extraValue}) {
  final names = <String>[
    for (final municipality in municipalities) municipality.name,
  ];
  if (extraValue != null &&
      extraValue.isNotEmpty &&
      extraValue != kProvinceWideValue &&
      !names.any((name) => name.toLowerCase() == extraValue.toLowerCase())) {
    names.add(extraValue);
  }
  return [
    const DropdownMenuItem<String?>(
      value: kProvinceWideValue,
      child: Text(kProvinceWideLabel),
    ),
    for (final name in names)
      DropdownMenuItem<String?>(value: name, child: Text(name)),
  ];
}
