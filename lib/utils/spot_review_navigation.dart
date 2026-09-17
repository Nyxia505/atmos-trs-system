import 'package:atmos_trs_system/models/spot_review.dart';
import 'package:atmos_trs_system/models/tourist_destination_detail.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/screens/tourist_destination_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Opens a tourist spot from a [SpotReview] row (Home feed, My Reviews, etc.).
Future<void> openSpotFromReview(BuildContext context, SpotReview review) async {
  final spotId = review.spotId.trim();
  if (spotId.isEmpty) return;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('tourist_spots')
        .doc(spotId)
        .get();
    if (!context.mounted) return;

    if (doc.exists && doc.data() != null) {
      final spot = TouristSpotFirestore.fromFirestore(doc.data()!, doc.id);
      final detail = TouristDestinationDetail.fromFirestoreSpot(spot);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TouristDestinationDetailScreen(
            destination: detail,
            firestoreSpot: spot,
          ),
        ),
      );
      return;
    }
  } catch (_) {
    if (!context.mounted) return;
  }

  final detail = TouristDestinationDetail.fromFeaturedMap({
    'spotId': spotId,
    'name': review.displaySpotName,
    'category': 'Spot',
    'description': '',
    'location': '',
    'rating': review.rating,
  });
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TouristDestinationDetailScreen(destination: detail),
    ),
  );
}
