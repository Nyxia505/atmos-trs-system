import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'data.dart';
import 'municipality_coordinates.dart' show getMunicipalityCoordinates;

class BudgetEvaluation {
  final bool withinBudget;
  final bool exactBudgetMatch;

  const BudgetEvaluation({
    required this.withinBudget,
    required this.exactBudgetMatch,
  });
}

/// Parses a peso amount from admin text (`50`, `₱50`, `Free`, etc.).
double? parsePesoAmountFromText(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return null;
  if (t == 'free' || t == 'n/a' || t == 'none' || t == '0') return 0;
  final values = RegExp(r'(\d+(?:\.\d+)?)')
      .allMatches(text)
      .map((m) => double.tryParse(m.group(1) ?? ''))
      .whereType<double>()
      .where((v) => v >= 0)
      .toList();
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a > b ? a : b);
}

/// Total visit cost from entrance + food & drinks + souvenirs (stored as [TouristSpot.priceRange]).
String computeSpotPriceRangeFromFees({
  required String entranceFee,
  required String foodAndDrinksPrice,
  String otherSouvenirsPrice = '',
}) {
  final entrance = parsePesoAmountFromText(entranceFee);
  final food = parsePesoAmountFromText(foodAndDrinksPrice);
  final souvenirs = parsePesoAmountFromText(otherSouvenirsPrice);
  final hasAny = entranceFee.trim().isNotEmpty ||
      foodAndDrinksPrice.trim().isNotEmpty ||
      otherSouvenirsPrice.trim().isNotEmpty;

  if (!hasAny) return 'Varies';

  final total = (entrance ?? 0) + (food ?? 0) + (souvenirs ?? 0);
  if (total <= 0) return 'Free';
  final rounded = total.round();
  return '₱$rounded';
}

/// Label for one fee row on spot detail (empty admin field → "Varies").
String formatSpotFeeForDisplay(String text) {
  final t = text.trim();
  if (t.isEmpty) return 'Varies';
  final lower = t.toLowerCase();
  if (lower == 'free' || lower == 'n/a' || lower == 'none') return 'Free';
  if (t.startsWith('₱')) return t;
  if (RegExp(r'^[\d\s.,\-–]+$').hasMatch(t)) return '₱$t';
  return t;
}

String normalizeMunicipalityName(String input) {
  return input
      .toLowerCase()
      .replaceAll('provincial capital', ' ')
      .replaceAll('city', ' ')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\bozamis\b'), 'ozamiz')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Set<String> municipalityAliases(Municipality municipality) {
  final aliases = <String>{
    normalizeMunicipalityName(municipality.name),
    normalizeMunicipalityName(municipality.shortName),
  };
  aliases.removeWhere((e) => e.isEmpty);
  return aliases;
}

/// Best municipality for a free-text locality (e.g. tourist `origin`). Uses the
/// longest matching alias so "Oroquieta City" wins over a shorter shared token.
Municipality? matchMunicipalityByLocalityHint(String rawHint) {
  final hint = rawHint.trim();
  if (hint.isEmpty) return null;
  final hn = normalizeMunicipalityName(hint);
  if (hn.isEmpty) return null;

  Municipality? best;
  var bestLen = -1;
  for (final m in municipalities) {
    for (final a in municipalityAliases(m)) {
      if (a.isEmpty) continue;
      if (hn == a || hn.contains(a) || a.contains(hn)) {
        if (a.length > bestLen) {
          bestLen = a.length;
          best = m;
        }
      }
    }
  }
  return best;
}

BudgetEvaluation evaluateBudgetFit(TouristSpot spot, double budget) {
  final values = _extractCurrencyValues(spot.priceRange);
  if (values.isEmpty) {
    return const BudgetEvaluation(withinBudget: true, exactBudgetMatch: false);
  }

  final minValue = values.reduce((a, b) => a < b ? a : b);
  final maxValue = values.reduce((a, b) => a > b ? a : b);
  final within = minValue <= budget;
  final exact = budget >= minValue && budget <= maxValue;
  return BudgetEvaluation(withinBudget: within, exactBudgetMatch: exact);
}

List<Municipality> municipalitiesAlongRoute({
  required Municipality start,
  required Municipality end,
  required List<LatLng> routePoints,
}) {
  final ordered = <Municipality>[];
  final seen = <String>{};

  void addMunicipality(Municipality m) {
    final key = normalizeMunicipalityName(m.name);
    if (seen.add(key)) ordered.add(m);
  }

  addMunicipality(start);

  if (routePoints.isNotEmpty) {
    for (final point in routePoints) {
      Municipality? nearest;
      double nearestKm = double.infinity;
      for (final m in municipalities) {
        final coord = getMunicipalityCoordinates(m);
        if (coord == null) continue;
        final km = _distanceKm(point, coord);
        if (km < nearestKm) {
          nearestKm = km;
          nearest = m;
        }
      }
      if (nearest != null && nearestKm <= 18.0) {
        addMunicipality(nearest);
      }
    }
  }

  addMunicipality(end);
  return ordered;
}

double _distanceKm(LatLng a, LatLng b) {
  const r = 6371.0;
  final dLat = _degToRad(b.latitude - a.latitude);
  final dLng = _degToRad(b.longitude - a.longitude);
  final aa =
      _sin2(dLat / 2) +
      math.cos(_degToRad(a.latitude)) *
          math.cos(_degToRad(b.latitude)) *
          _sin2(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
  return r * c;
}

double _degToRad(double deg) => deg * 0.017453292519943295;
double _sin2(double x) {
  final s = math.sin(x);
  return s * s;
}

List<double> _extractCurrencyValues(String text) {
  final matches = RegExp(r'(\d+(?:\.\d+)?)').allMatches(text);
  return matches
      .map((m) => double.tryParse(m.group(1) ?? ''))
      .whereType<double>()
      .toList();
}
