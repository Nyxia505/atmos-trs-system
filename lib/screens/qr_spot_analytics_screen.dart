import 'package:flutter/material.dart';

import 'package:atmos_trs_system/services/local_qr_spot_checkin_service.dart';

class QrSpotAnalyticsScreen extends StatelessWidget {
  const QrSpotAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = LocalQRSpotCheckInService.instance;
    final spotCounts = service.totalVisitsPerSpot();
    final municipalityCounts = service.totalVisitsPerMunicipality();
    final today = DateTime.now();
    final todayCount = service.dailyVisitCount(today);
    final monthCount = service.monthlyVisitCount(today.year, today.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Check-in Analytics'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Today\'s visits: $todayCount'),
          Text('This month\'s visits: $monthCount'),
          const SizedBox(height: 16),
          const Text(
            'Total visits per spot',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...spotCounts.entries.map(
            (e) => ListTile(
              title: Text(e.key),
              trailing: Text(e.value.toString()),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Total visits per municipality',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...municipalityCounts.entries.map(
            (e) => ListTile(
              title: Text(e.key),
              trailing: Text(e.value.toString()),
            ),
          ),
        ],
      ),
    );
  }
}

