import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:atmos_trs_system/models/establishment_map_pin.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/services/establishment_gallery_service.dart';
import 'package:atmos_trs_system/services/establishment_map_pin_store.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';

/// Streams OPTACA-approved establishments for the tourist Explore map.
///
/// Coordinates prefer Supabase `map_pin.json` (free-tier safe); Firestore lat/lng
/// are a fallback when no Supabase pin exists yet.
class EstablishmentMapPinsService {
  EstablishmentMapPinsService._();

  static double _asDouble(dynamic raw) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static EstablishmentMapPin? _baseFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required double latitude,
    required double longitude,
  }) {
    final d = doc.data() ?? const <String, dynamic>{};
    final status =
        EstablishmentRegistryStatus.normalize(d['status']?.toString());
    if (!EstablishmentRegistryStatus.isActive(status)) return null;
    if (latitude.abs() < 1e-6 && longitude.abs() < 1e-6) return null;
    final name = (d['businessName'] ?? d['name'] ?? 'Establishment')
        .toString()
        .trim();
    final gallery = EstablishmentGalleryService.parseUrls(d['galleryUrls']);
    final cover = (d['coverImageUrl'] ?? '').toString().trim();
    return EstablishmentMapPin(
      id: doc.id,
      name: name.isEmpty ? 'Establishment' : name,
      category: (d['category'] ?? d['type'] ?? '').toString(),
      latitude: latitude,
      longitude: longitude,
      municipality: (d['municipality'] ?? '').toString(),
      barangay: (d['barangay'] ?? '').toString(),
      location: (d['location'] ?? '').toString(),
      coverImageUrl: cover.startsWith('http')
          ? cover
          : (gallery.isNotEmpty ? gallery.first : ''),
      galleryUrls: gallery,
    );
  }

  static Future<EstablishmentMapPin?> _resolvePin(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final d = doc.data() ?? const <String, dynamic>{};
    final status =
        EstablishmentRegistryStatus.normalize(d['status']?.toString());
    if (!EstablishmentRegistryStatus.isActive(status)) return null;

    final fsLat = _asDouble(d['latitude']);
    final fsLng = _asDouble(d['longitude']);
    final supabase = await EstablishmentMapPinStore.load(doc.id);
    final lat = supabase?.latitude ?? fsLat;
    final lng = supabase?.longitude ?? fsLng;
    return _baseFromDoc(doc, latitude: lat, longitude: lng);
  }

  /// Live pins for tourist Explore map (active + coordinates).
  static Stream<List<EstablishmentMapPin>> watchActivePins() {
    return FirebaseFirestore.instance
        .collection(EstablishmentRegistrationService.establishmentsCollection)
        .snapshots()
        .asyncMap((snap) async {
      final futures = snap.docs.map(_resolvePin);
      final resolved = await Future.wait(futures);
      final out = resolved.whereType<EstablishmentMapPin>().toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    });
  }

  /// One-shot load for detail screen refresh.
  static Future<EstablishmentMapPin?> getById(String establishmentId) async {
    final id = establishmentId.trim();
    if (id.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(EstablishmentRegistrationService.establishmentsCollection)
          .doc(id)
          .get();
      if (!doc.exists) return null;
      return _resolvePin(doc);
    } catch (_) {
      return null;
    }
  }
}
