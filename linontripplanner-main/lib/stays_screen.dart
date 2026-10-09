import 'package:flutter/material.dart';
import 'data.dart';
import 'spot_detail_screen.dart';
import 'widgets/municipality_image.dart';

class StaysScreen extends StatefulWidget {
  const StaysScreen({super.key});

  @override
  State<StaysScreen> createState() => _StaysScreenState();
}

class _StaysScreenState extends State<StaysScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['All', 'Hotels', 'Resorts', 'Nature'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<TouristSpot> _filteredSpots(String tab) {
    if (tab == 'All') return allSpots;
    if (tab == 'Hotels') return allSpots.where((s) => s.isHotel).toList();
    if (tab == 'Nature') return allSpots.where((s) => !s.isHotel).toList();
    return allSpots;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Stays & Hotels',
          style: TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: TabBarView(
            controller: _tabController,
            children: _tabs.map((tab) {
              final spots = _filteredSpots(tab);
              return spots.isEmpty
                  ? const Center(
                      child: Text('No results found.',
                          style: TextStyle(color: AppColors.textGrey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: spots.length,
                      itemBuilder: (context, index) {
                        final spot = spots[index];
                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => SpotDetailScreen(spot: spot)),
                          ),
                          child: _StayCard(spot: spot),
                        );
                      },
                    );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _StayCard extends StatelessWidget {
  final TouristSpot spot;
  const _StayCard({required this.spot});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spot profile picture
          Stack(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: buildTouristSpotProfileImage(
                    spot,
                    fallback: Container(
                      color: AppColors.primary.withOpacity(0.08),
                      child: const Center(
                        child: Icon(
                          Icons.hotel,
                          size: 40,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: spot.isHotel
                        ? Colors.blue.shade600
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    spot.isHotel ? '🏨 Hotel' : '🌿 ${spot.type}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          // Info
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(spot.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark)),
                    ),
                    StarRating(rating: spot.rating, size: 14),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(spot.location,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textGrey)),
                    const Spacer(),
                    Text(spot.priceRange,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
