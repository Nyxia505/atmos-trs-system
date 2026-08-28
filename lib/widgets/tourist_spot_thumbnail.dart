import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:flutter/material.dart';

/// Thumbnail for tourist spot list/detail cards (assets + network).
Widget touristSpotThumbnail(
  String? imageUrl, {
  required double size,
  BorderRadius? borderRadius,
  String? spotId,
  String? spotName,
  String? municipalityId,
  String? category,
  String? city,
}) {
  final mid = municipalityId?.trim().isNotEmpty == true
      ? municipalityId
      : getMunicipalityIdFromName(city ?? spotName);

  return SpotImage(
    imageUrl: imageUrl,
    spotId: spotId,
    spotName: spotName,
    municipalityId: mid,
    category: category,
    width: size,
    height: size,
    borderRadius: borderRadius ?? BorderRadius.circular(8),
  );
}
