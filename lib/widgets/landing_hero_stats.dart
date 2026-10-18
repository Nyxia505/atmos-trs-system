import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum LandingStatStatus { loading, ready, unavailable }

class LandingStatEntry {
  const LandingStatEntry({
    required this.label,
    required this.icon,
    required this.status,
    this.value,
  });

  final String label;
  final IconData icon;
  final LandingStatStatus status;
  final int? value;
}

/// Compact public totals opened from the landing hero. Counts only — no names.
class LandingHeroStatsPanel extends StatelessWidget {
  const LandingHeroStatsPanel({
    super.key,
    required this.entries,
    required this.onClose,
  });

  final List<LandingStatEntry> entries;
  final VoidCallback onClose;

  static const orange = Color(0xFFF97316);
  static const navy = Color(0xFF1B2433);

  static String formatCount(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  @override
  Widget build(BuildContext context) {
    final waiting = entries.every((e) => e.status == LandingStatStatus.loading);
    final unavailable = entries.every(
      (e) => e.status == LandingStatStatus.unavailable,
    );

    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights_rounded, color: orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'By the numbers',
                      style: GoogleFonts.montserrat(
                        color: navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
              if (waiting)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 12, 8),
                  child: Text(
                    'Loading public totals…',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                )
              else if (unavailable)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 12, 8),
                  child: Text(
                    'Public totals are unavailable right now.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              for (final entry in entries) _StatRow(entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.entry});

  final LandingStatEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: LandingHeroStatsPanel.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(entry.icon, size: 16, color: LandingHeroStatsPanel.orange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.label,
              style: GoogleFonts.montserrat(
                color: const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _value(entry),
        ],
      ),
    );
  }

  Widget _value(LandingStatEntry entry) {
    if (entry.status == LandingStatStatus.loading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: LandingHeroStatsPanel.orange,
        ),
      );
    }
    if (entry.status != LandingStatStatus.ready || entry.value == null) {
      return Text(
        '—',
        style: GoogleFonts.montserrat(
          color: LandingHeroStatsPanel.navy,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    return Text(
      LandingHeroStatsPanel.formatCount(entry.value!),
      style: GoogleFonts.montserrat(
        color: LandingHeroStatsPanel.navy,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
