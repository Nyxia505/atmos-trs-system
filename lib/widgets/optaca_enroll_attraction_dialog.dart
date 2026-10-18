import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/services/tourist_spots_firestore_service.dart';
import 'package:atmos_trs_system/utils/spot_qr_export.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// OPTACA enrolls a new attraction and stores its check-in QR on the spot.
Future<void> showOptacaEnrollAttractionDialog({
  required BuildContext context,
  required VoidCallback onEnrolled,
}) async {
  final pageContext = context;
  final nameController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();
  final codeController = TextEditingController();
  var municipalityId = getMisamisOccidentalMunicipalities().first.id;
  var category = 'Beach';
  var saving = false;

  const categories = [
    'Beach',
    'Falls',
    'Historical',
    'Mountain',
    'Resort',
    'Attraction',
  ];

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> save() async {
              final name = nameController.text.trim();
              final lat = double.tryParse(latController.text.trim());
              final lng = double.tryParse(lngController.text.trim());
              if (name.isEmpty || lat == null || lng == null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Name, latitude, and longitude are required.'),
                  ),
                );
                return;
              }
              setLocal(() => saving = true);
              final municipality = getMisamisOccidentalMunicipalities()
                  .firstWhere((m) => m.id == municipalityId);
              final result = await TouristSpotsFirestoreService.addSpotDetailed(
                TouristSpot(
                  id: '',
                  name: name,
                  category: category,
                  municipality: municipality.name,
                  description: '',
                  rating: 0,
                  latitude: lat,
                  longitude: lng,
                  municipalityId: municipalityId,
                  status: 'Active',
                  dotAttractionCode: codeController.text.trim(),
                ),
              );
              if (!dialogContext.mounted) return;
              setLocal(() => saving = false);
              if (!result.ok || result.id == null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(result.error ?? 'Could not enroll the attraction.'),
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop();
              onEnrolled();
              if (!pageContext.mounted) return;
              await showDialog<void>(
                context: pageContext,
                builder: (qrContext) => AlertDialog(
                  title: Text(name),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'QR is saved on this attraction. Print it for the site.',
                      ),
                      const SizedBox(height: 12),
                      QrImageView(
                        data: screenPreviewQrData(
                          spotQrData(
                            municipalityId,
                            result.id!,
                            latitude: lat,
                            longitude: lng,
                          ),
                        ),
                        size: 180,
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => downloadSpotQrPng(
                        municipalityId,
                        result.id!,
                        latitude: lat,
                        longitude: lng,
                      ),
                      child: const Text('PNG'),
                    ),
                    TextButton(
                      onPressed: () => downloadSpotQrPdf(
                        municipalityId: municipalityId,
                        spotId: result.id!,
                        spotName: name,
                        municipalityDisplayName: municipality.name,
                        latitude: lat,
                        longitude: lng,
                      ),
                      child: const Text('PDF'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(qrContext),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: const Text('Enroll attraction QR'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Attraction name',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: municipalityId,
                        decoration: const InputDecoration(labelText: 'Municipality'),
                        items: [
                          for (final m in getMisamisOccidentalMunicipalities())
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                        ],
                        onChanged: saving
                            ? null
                            : (value) => setLocal(
                                  () => municipalityId = value ?? municipalityId,
                                ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: [
                          for (final item in categories)
                            DropdownMenuItem(value: item, child: Text(item)),
                        ],
                        onChanged: saving
                            ? null
                            : (value) =>
                                setLocal(() => category = value ?? category),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: latController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Latitude'),
                      ),
                      TextField(
                        controller: lngController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Longitude'),
                      ),
                      TextField(
                        controller: codeController,
                        decoration: const InputDecoration(
                          labelText: 'DOT attraction code (optional)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : save,
                  style: FilledButton.styleFrom(
                    backgroundColor: GovernorDashboardTokens.primary,
                  ),
                  child: Text(saving ? 'Saving…' : 'Enroll QR'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    nameController.dispose();
    latController.dispose();
    lngController.dispose();
    codeController.dispose();
  }
}
