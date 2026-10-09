/// Official Misamis Occidental inter-LGU fare matrix (estimated jeepney/bus fares in PHP).
///
/// Row index = origin, column index = destination. Diagonal entries are ₱0 (same LGU).
const List<String> kFareMatrixMunicipalityKeys = [
  'Aloran',
  'Baliangao',
  'Bonifacio',
  'Calamba',
  'Clarin',
  'Concepcion',
  'Don Victoriano Chiongbian',
  'Jimenez',
  'Lopez Jaena',
  'Oroquieta City',
  'Ozamiz City',
  'Panaon',
  'Plaridel',
  'Sapang Dalaga',
  'Sinacaban',
  'Tangub City',
  'Tudela',
];

/// Maps fare-matrix labels to canonical [Municipality.name] values in [data.dart].
const Map<String, String> kFareMatrixKeyToMunicipalityName = {
  'Oroquieta City': 'Oroquieta City (Provincial Capital)',
};

/// Maps app municipality names back to matrix keys for fare lookup.
String fareMatrixKeyForMunicipalityName(String municipalityName) {
  final trimmed = municipalityName.trim();
  if (trimmed.startsWith('Oroquieta')) return 'Oroquieta City';
  return trimmed;
}

/// Canonical app name used in Firestore and [municipalities].
String canonicalMunicipalityNameFromMatrixKey(String matrixKey) {
  return kFareMatrixKeyToMunicipalityName[matrixKey] ?? matrixKey;
}

/// Symmetric matrix stored row-major (same order as [kFareMatrixMunicipalityKeys]).
const List<List<int>> kMisamisOccidentalFareMatrixPhp = [
  [0, 140, 80, 100, 50, 120, 220, 40, 110, 90, 50, 130, 70, 100, 40, 60, 30],
  [140, 0, 70, 40, 120, 30, 180, 130, 40, 60, 140, 20, 90, 50, 130, 120, 135],
  [80, 70, 0, 40, 60, 80, 150, 70, 60, 50, 90, 75, 40, 70, 85, 70, 75],
  [100, 40, 40, 0, 80, 50, 170, 90, 30, 40, 110, 40, 60, 40, 100, 90, 95],
  [50, 120, 60, 80, 0, 100, 200, 35, 90, 70, 25, 110, 50, 80, 30, 45, 20],
  [120, 30, 80, 50, 100, 0, 190, 110, 35, 50, 120, 25, 80, 45, 115, 100, 110],
  [220, 180, 150, 170, 200, 190, 0, 190, 170, 160, 210, 185, 170, 180, 205, 190, 195],
  [40, 130, 70, 90, 35, 110, 190, 0, 100, 80, 40, 120, 60, 90, 35, 50, 25],
  [110, 40, 60, 30, 90, 35, 170, 100, 0, 30, 100, 35, 70, 30, 95, 85, 90],
  [90, 60, 50, 40, 70, 50, 160, 80, 30, 0, 80, 55, 50, 40, 75, 65, 70],
  [50, 140, 90, 110, 25, 120, 210, 40, 100, 80, 0, 130, 70, 100, 30, 60, 25],
  [130, 20, 75, 40, 110, 25, 185, 120, 35, 55, 130, 0, 85, 40, 120, 110, 120],
  [70, 90, 40, 60, 50, 80, 170, 60, 70, 50, 70, 85, 0, 60, 65, 55, 60],
  [100, 50, 70, 40, 80, 45, 180, 90, 30, 40, 100, 40, 60, 0, 90, 80, 85],
  [40, 130, 85, 100, 30, 115, 205, 35, 95, 75, 30, 120, 65, 90, 0, 40, 20],
  [60, 120, 70, 90, 45, 100, 190, 50, 85, 65, 60, 110, 55, 80, 40, 0, 45],
  [30, 135, 75, 95, 20, 110, 195, 25, 90, 70, 25, 120, 60, 85, 20, 45, 0],
];

int? farePhpBetweenMatrixKeys(String fromKey, String toKey) {
  final fromIdx = kFareMatrixMunicipalityKeys.indexOf(fromKey);
  final toIdx = kFareMatrixMunicipalityKeys.indexOf(toKey);
  if (fromIdx < 0 || toIdx < 0) return null;
  return kMisamisOccidentalFareMatrixPhp[fromIdx][toIdx];
}
