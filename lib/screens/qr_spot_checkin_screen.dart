import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/qr_tourist_spot.dart';
import 'package:atmos_trs_system/services/local_qr_spot_checkin_service.dart';
import 'package:atmos_trs_system/config/session_storage.dart';

class QrSpotCheckInScreen extends StatelessWidget {
  const QrSpotCheckInScreen({
    super.key,
    required this.spot,
  });

  final QrTouristSpot spot;

  Future<String?> _getUserId() async {
    return SessionStorage.getStoredUser();
  }

  @override
  Widget build(BuildContext context) {
    final service = LocalQRSpotCheckInService.instance;

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
              label: const Text('Check In'),
              onPressed: () async {
                final userId = await _getUserId() ?? 'mock_user';
                final ok = service.checkIn(userId: userId, spot: spot);
                final msg = ok
                    ? 'Check-in successful!'
                    : 'You have already checked in here today.';
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

