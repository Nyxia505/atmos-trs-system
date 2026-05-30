import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/qr_tourist_spot.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

class QrSpotCheckInScreen extends StatelessWidget {
  const QrSpotCheckInScreen({
    super.key,
    required this.spot,
  });

  final QrTouristSpot spot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(spot.name),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.asset(
              spot.image,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Colors.grey,
                child: Center(
                  child: Icon(Icons.photo, size: 48, color: Colors.white70),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  spot.municipality,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  spot.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Register visit'),
              onPressed: () async {
                final municipalityId =
                    getMunicipalityIdFromName(spot.municipality);
                if (municipalityId.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Cannot check in: municipality mapping not found.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  return;
                }
                await performQRCheckIn(
                  context,
                  municipalityId: municipalityId,
                  spotId: spot.id,
                  spotName: spot.name,
                  municipality: spot.municipality,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

