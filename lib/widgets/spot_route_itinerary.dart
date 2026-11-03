import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/utils/spot_route_destination.dart';
import 'package:flutter/material.dart';

/// Start → towns along the way → end, using the Trip Planner road path.
class SpotRouteItinerary extends StatelessWidget {
  const SpotRouteItinerary({
    super.key,
    required this.places,
    this.compact = false,
  });

  final SpotRoutePlaces places;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stop(
          icon: Icons.my_location_rounded,
          title: 'Starting point',
          name: places.startLabel,
          detail: places.startTown,
          color: accent,
        ),
        if (places.hasViaTowns) ...[
          _connector(accent),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Places along the way',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: AppTheme.unselectedMuted,
                  ),
                ),
                const SizedBox(height: 6),
                if (compact)
                  Text(
                    places.viaTowns.join(' → '),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  )
                else
                  for (var i = 0; i < places.viaTowns.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == places.viaTowns.length - 1 ? 0 : 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: accent.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              places.viaTowns[i],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
        _connector(accent),
        _stop(
          icon: Icons.flag_rounded,
          title: 'End point',
          name: places.endLabel,
          detail: places.endTown,
          color: accent,
        ),
      ],
    );
  }

  Widget _connector(Color accent) {
    return Padding(
      padding: const EdgeInsets.only(left: 15, top: 2, bottom: 2),
      child: Container(
        width: 2,
        height: 14,
        color: accent.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _stop({
    required IconData icon,
    required String title,
    required String name,
    required String detail,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: AppTheme.unselectedMuted,
                ),
              ),
              Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (detail.isNotEmpty &&
                  detail.toLowerCase() != name.toLowerCase())
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.unselectedMuted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
