import 'dart:typed_data';

import 'package:atmos_trs_system/services/spot_qr_poster_pdf.dart';
import 'package:atmos_trs_system/utils/png_bytes_download.dart';
import 'package:atmos_trs_system/utils/spot_qr_poster.dart';
import 'package:atmos_trs_system/utils/spot_qr_poster_png.dart';
import 'package:printing/printing.dart';

SpotQrPosterData _posterData({
  required String municipalityId,
  required String spotId,
  required String spotName,
  required String municipalityDisplayName,
  String? qrPayload,
  String? category,
  double? latitude,
  double? longitude,
}) {
  return buildSpotQrPosterData(
    municipalityId: municipalityId,
    spotId: spotId,
    spotName: spotName,
    municipalityDisplayName: municipalityDisplayName,
    qrPayload: qrPayload,
    category: category,
    latitude: latitude,
    longitude: longitude,
  );
}

/// Downloads a complete A4 ATMOS TRS QR check-in poster as PNG.
Future<void> downloadSpotQrPng(
  String municipalityId,
  String spotId, {
  String spotName = '',
  String municipalityDisplayName = '',
  String? qrPayload,
  String? category,
  double? latitude,
  double? longitude,
  Future<void> Function()? onPrepared,
}) async {
  final data = _posterData(
    municipalityId: municipalityId,
    spotId: spotId,
    spotName: spotName,
    municipalityDisplayName: municipalityDisplayName,
    qrPayload: qrPayload,
    category: category,
    latitude: latitude,
    longitude: longitude,
  );
  final bytes = await renderSpotQrPosterPng(data);
  if (onPrepared != null) await onPrepared();
  await downloadPngFile(
    spotQrPosterFilename(data.displayName, 'png'),
    bytes,
  );
}

/// Single-page A4 PDF of the same QR check-in poster.
Future<void> downloadSpotQrPdf({
  required String municipalityId,
  required String spotId,
  required String spotName,
  required String municipalityDisplayName,
  String? qrPayload,
  String? category,
  double? latitude,
  double? longitude,
  Future<void> Function()? onPrepared,
}) async {
  final data = _posterData(
    municipalityId: municipalityId,
    spotId: spotId,
    spotName: spotName,
    municipalityDisplayName: municipalityDisplayName,
    qrPayload: qrPayload,
    category: category,
    latitude: latitude,
    longitude: longitude,
  );
  final Uint8List bytes = await renderSpotQrPosterPdf(data);
  if (onPrepared != null) await onPrepared();
  await Printing.layoutPdf(
    onLayout: (format) async => bytes,
    name: spotQrPosterFilename(data.displayName, 'pdf'),
  );
}
