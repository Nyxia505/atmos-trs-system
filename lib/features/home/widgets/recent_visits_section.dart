import 'package:flutter/material.dart';
import 'package:atmos_trs_system/models/destination.dart';
import 'package:atmos_trs_system/features/home/widgets/destination_card.dart';
import 'package:atmos_trs_system/features/navigation/placeholder_pages.dart';

/// "Your History" header (small + "Recent Visits" big) with "See All" on the right; horizontal list of destination cards.
class RecentVisitsSection extends StatelessWidget {
  const RecentVisitsSection({
    super.key,
    required this.destinations,
    this.sectionTitle = 'Recent Visits',
    this.cardWidth = 180,
    this.onSeeAll,
  });

  final List<Destination> destinations;
  final String sectionTitle;
  final double cardWidth;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = _horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 28, horizontalPadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR HISTORY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sectionTitle,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onSeeAll ?? () => _navigateToSeeAll(context),
                child: const Text('See All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: destinations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'No destinations match your search. Try another category or clear the search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: destinations.length,
                    itemBuilder: (context, index) {
                      return DestinationCard(
                        destination: destinations[index],
                        cardWidth: cardWidth,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _navigateToSeeAll(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SeeAllPage()),
    );
  }

  static double _horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 48;
    if (w >= 600) return 32;
    return 20;
  }
}
