import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'firestore_loader.dart';
import 'municipality_detail_screen.dart';
import 'widgets/municipality_image.dart';
import 'widgets/tourism_plan_ui.dart';

class MunicipalityListScreen extends StatelessWidget {
  final int selectedIndex;
  /// When true (bottom-nav tab), hide the back button so Home shell stays put.
  final bool embeddedInShell;

  const MunicipalityListScreen({
    super.key,
    this.selectedIndex = -1,
    this.embeddedInShell = false,
  });

  static String _touristCountLabel(int n) {
    if (n == 1) return '1 tourist';
    return '$n tourists';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Municipalities'),
        automaticallyImplyLeading: !embeddedInShell,
        leading: embeddedInShell
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: AppColors.textDark,
                  size: 28,
                ),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: TourismPlanPageBody(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(kTouristCollection)
            .snapshots(),
        builder: (context, touristSnap) {
          final counts = touristSnap.hasData
              ? touristCountsPerMunicipalityFromTouristDocs(
                  touristSnap.data!.docs,
                )
              : <String, int>{
                  for (final m in sortedMunicipalities) m.name: 0,
                };

          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final maxContent = 1100.0;
              final contentW = w > maxContent ? maxContent : w;

              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentW,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: sortedMunicipalities.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return TourismPlanCard(
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: TourismPlanUi.primaryGradient,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.map_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Misamis Occidental',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${sortedMunicipalities.length} municipalities & cities',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final m = sortedMunicipalities[index - 1];
                      final n = counts[m.name] ?? 0;
                      final isCity = m.divisionLabel == 'City';
                      return TourismPeachListTile(
                        title: m.name,
                        subtitle:
                            '${m.divisionLabel} · ${_touristCountLabel(n)}',
                        icon: isCity
                            ? Icons.location_city_rounded
                            : Icons.domain_rounded,
                        leading: ClipOval(
                          child: SizedBox(
                            width: 46,
                            height: 46,
                            child: buildMunicipalityImageForMunicipality(
                              m,
                              memCacheWidth: 92,
                              memCacheHeight: 92,
                              fallback: Container(
                                color: AppColors.primary
                                    .withValues(alpha: 0.12),
                                child: Icon(
                                  isCity
                                      ? Icons.location_city_rounded
                                      : Icons.domain_rounded,
                                  color: AppColors.primary,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                MunicipalityDetailScreen(municipality: m),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      ),
    );
  }
}
