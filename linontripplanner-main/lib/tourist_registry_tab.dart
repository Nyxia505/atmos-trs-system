import 'package:flutter/material.dart';

import 'data.dart';
import 'firestore_loader.dart';
import 'services/admin_live_collections.dart';
import 'theme/tourism_app_theme.dart';
import 'widgets/optaca_portal_ui.dart';

/// Governor portal: live table of documents in the Firestore `tourists` collection.
class TouristRegistryTab extends StatefulWidget {
  const TouristRegistryTab({super.key});

  @override
  State<TouristRegistryTab> createState() => _TouristRegistryTabState();
}

class _TouristRegistryTabState extends State<TouristRegistryTab> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const _accent = OptacaAdminTheme.primary;
  static const _tableBorder = OptacaAdminTheme.border;

  void _showDetails(
    BuildContext context,
    TouristRegistryEntry e, {
    required int displayVisits,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailLine('Document ID', e.docId),
              _detailLine('Tourist ID', e.touristId),
              _detailLine('Origin', e.origin),
              _detailLine('Date', e.dateDisplay),
              _detailLine('Time', e.timeDisplay),
              _detailLine('Visits', displayVisits.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Container(
        decoration: OptacaAdminTheme.cardDecoration,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Registered tourists',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: OptacaAdminTheme.text,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                style: const TextStyle(fontSize: 13),
                onChanged: (_) => setState(() {}),
                decoration: OptacaPortalUi.searchDecoration(
                  hint: 'Search tourists...',
                  suffixIcon: IconButton(
                    tooltip: 'Voice search',
                    icon: const Icon(Icons.mic_none_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Voice search is not configured.'),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, viewport) {
                    const kTableMinScrollWidth = 860.0;
                    final available = viewport.maxWidth.isFinite
                        ? viewport.maxWidth
                        : kTableMinScrollWidth;
                    final tableWidth = available < kTableMinScrollWidth
                        ? kTableMinScrollWidth
                        : available;

                    return AdminLiveDataBuilder(
                      builder: (context, live) {
                        if (live.touristsError != null &&
                            live.touristsReady &&
                            live.tourists.isEmpty) {
                          return OptacaLoadError(
                            title: 'Could not load tourists',
                            message: '${live.touristsError}',
                            onRetry: live.retry,
                          );
                        }
                        if (!live.touristsReady) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final visitCounts = live.checkInsReady
                            ? touristVisitCountsFromCheckInDocs(live.checkIns)
                            : const <String, int>{};

                        final entries = live.tourists
                            .map(touristRegistryEntryFromDoc)
                            .toList()
                          ..sort((a, b) => b.sortKey.compareTo(a.sortKey));

                        final q = _search.text;
                        final filtered = entries
                            .where(
                              (e) => e.matchesSearch(
                                q,
                                visitsOverride: _mergedVisitCount(
                                  e,
                                  visitCounts,
                                ),
                              ),
                            )
                            .toList();

                        if (entries.isEmpty) {
                          return const OptacaEmptyState(
                            icon: Icons.people_outline_rounded,
                            title: 'No tourists yet',
                            message:
                                'Add documents to the Firestore tourists collection.',
                          );
                        }

                        if (filtered.isEmpty) {
                          return const OptacaEmptyState(
                            icon: Icons.search_off_outlined,
                            title: 'No matching tourists',
                            message: 'No rows match your search.',
                          );
                        }

                        return Scrollbar(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: SizedBox(
                                width: tableWidth,
                                child: Table(
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              border: TableBorder(
                                top: BorderSide(
                                  color: _tableBorder.withValues(alpha: 0.85),
                                  width: 1),
                                left: BorderSide(
                                  color: _tableBorder.withValues(alpha: 0.85),
                                  width: 1),
                                right: BorderSide(
                                  color: _tableBorder.withValues(alpha: 0.85),
                                  width: 1),
                                bottom: BorderSide(
                                  color: _tableBorder.withValues(alpha: 0.85),
                                  width: 1),
                                horizontalInside: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 0.5,
                                ),
                                verticalInside: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 0.5,
                                ),
                              ),
                              columnWidths: const {
                                0: FlexColumnWidth(1.2),
                                1: FlexColumnWidth(0.95),
                                2: FlexColumnWidth(1.05),
                                3: FlexColumnWidth(0.62),
                                4: FlexColumnWidth(0.78),
                                5: FlexColumnWidth(0.36),
                                6: FixedColumnWidth(72),
                              },
                              children: [
                                TableRow(
                                  decoration: const BoxDecoration(
                                    color: OptacaAdminTheme.lightOrange,
                                  ),
                                  children: [
                                    _th('Name'),
                                    _th('Tourist ID'),
                                    _th('Origin'),
                                    _th('Date'),
                                    _th('Time'),
                                    _th('Visits'),
                                    _th('Actions'),
                                  ],
                                ),
                                  for (final e in filtered)
                                    _dataRow(
                                      context,
                                      e,
                                      displayVisits: _mergedVisitCount(
                                        e,
                                        visitCounts,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _th(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11.5,
          height: 1.1,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  static const _cellStyle = TextStyle(
    fontSize: 12,
    height: 1.15,
    color: AppColors.textDark,
  );

  /// Prefer QR check-in counts (including tourism-dashboard seed rows); else the field on the tourist doc.
  static int _mergedVisitCount(
    TouristRegistryEntry e,
    Map<String, int> visitCounts,
  ) {
    final byTouristId = visitCounts[e.touristId] ?? 0;
    final byDocId = visitCounts[e.docId] ?? 0;
    final fromCollection =
        byTouristId > byDocId ? byTouristId : byDocId;
    if (fromCollection > 0) return fromCollection;
    return e.visits;
  }

  TableRow _dataRow(
    BuildContext context,
    TouristRegistryEntry e, {
    required int displayVisits,
  }) {
    return TableRow(
      children: [
        _td(Text(
          e.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _cellStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        )),
        _td(Text(
          e.touristId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _cellStyle.copyWith(
            color: _accent,
            fontWeight: FontWeight.w600,
          ),
        )),
        _td(Text(
          e.origin,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _cellStyle.copyWith(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w400,
          ),
        )),
        _td(Text(
          e.dateDisplay,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _cellStyle,
        )),
        _td(Text(
          e.timeDisplay,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _cellStyle,
        )),
        _td(
          Align(
            alignment: Alignment.center,
            child: Text(
              displayVisits.toString(),
              maxLines: 1,
              style: _cellStyle,
            ),
          ),
        ),
        _td(
          Center(
            child: Tooltip(
              message: 'View',
              child: Material(
                color: _accent.withValues(alpha: 0.12),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showDetails(
                    context,
                    e,
                    displayVisits: displayVisits,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(
                      Icons.visibility_outlined,
                      color: _accent,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _td(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: child,
    );
  }
}
