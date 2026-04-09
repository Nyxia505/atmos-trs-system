import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';

class ItineraryPage extends StatelessWidget {
  const ItineraryPage({super.key});

  static const Color _primaryOrange = Color(0xFFF97316);
  static const Color _accentOrange = Color(0xFFFB923C);
  static const Color _darkBg = Color(0xFF0F172A);

  /// Sample itinerary data for display.
  static final List<Map<String, String>> _sampleItineraries = [
    {
      'destination': 'Oroquieta City',
      'date': 'Mar 20, 2026',
      'notes': 'Capital city tour, plaza and local cuisine',
    },
    {
      'destination': 'Baliangao',
      'date': 'Mar 22, 2026',
      'notes': 'Cabgan Island and beach day',
    },
    {
      'destination': 'Sapang Dalaga',
      'date': 'Mar 25, 2026',
      'notes': 'Caluya Bay and Cristo Redentor',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Itinerary Planner'),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 20 : 32,
          vertical: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Create Trip button
            Center(
              child: SizedBox(
                width: isMobile ? double.infinity : 220,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Placeholder for create trip flow
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Create Trip coming soon'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded, size: 22),
                  label: const Text('Create Trip'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // My Itinerary section header
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 16),
              child: Text(
                'My Itinerary',
                style: TextStyle(
                  color: _darkBg,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Sample itinerary cards
            ..._sampleItineraries.map((item) => _buildItineraryCard(
                  context,
                  destination: item['destination']!,
                  date: item['date']!,
                  notes: item['notes']!,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildItineraryCard(
    BuildContext context, {
    required String destination,
    required String date,
    required String notes,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primaryOrange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.place_rounded,
                        color: _primaryOrange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        destination,
                        style: const TextStyle(
                          color: _darkBg,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text(
                      date,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Notes',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notes,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
