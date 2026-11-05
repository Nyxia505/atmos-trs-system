import 'package:flutter/material.dart';

import '../data.dart';
import '../event_schedule.dart';
import '../widgets/municipality_image.dart';
import '../widgets/tourism_events_calendar.dart' show openTourismEventDetail;

/// Informational dialog listing OPTACA events that overlap the trip.
Future<void> showTripTravelEventsDialog(
  BuildContext context, {
  required List<TourismEvent> events,
  required Color accent,
}) {
  if (events.isEmpty) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, anim, secondary) {
      return SafeArea(
        child: Center(
          child: _TripTravelEventsDialogBody(
            events: events,
            accent: accent,
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _TripTravelEventsDialogBody extends StatelessWidget {
  const _TripTravelEventsDialogBody({
    required this.events,
    required this.accent,
  });

  final List<TourismEvent> events;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.82;
    final maxW = MediaQuery.sizeOf(context).width.clamp(280.0, 520.0);

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.celebration_rounded,
                        color: accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Events During Your Trip!',
                            style: TextStyle(
                              fontFamily: AppFonts.holidayCalling,
                              fontSize: 24,
                              height: 1.1,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            events.length == 1
                                ? 'We found 1 upcoming event happening during your selected travel dates. You might want to check it out!'
                                : 'We found ${events.length} upcoming events happening during your selected travel dates. You might want to check them out!',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              color: AppColors.textGrey.withValues(alpha: 0.98),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.textGrey.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _EventMatchCard(
                      event: events[index],
                      accent: accent,
                      index: index + 1,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 360;
                    final gotIt = FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        minimumSize: Size(narrow ? double.infinity : 0, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Got It',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                    final viewDetails = OutlinedButton(
                      onPressed: () {
                        final first = events.first;
                        Navigator.of(context).maybePop().then((_) {
                          if (!context.mounted) return;
                          openTourismEventDetail(
                            context,
                            first,
                            accentColor: accent,
                          );
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withValues(alpha: 0.55)),
                        minimumSize: Size(narrow ? double.infinity : 0, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'View Event Details',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          gotIt,
                          const SizedBox(height: 8),
                          viewDetails,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: viewDetails),
                        const SizedBox(width: 10),
                        Expanded(child: gotIt),
                      ],
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
}

class _EventMatchCard extends StatelessWidget {
  const _EventMatchCard({
    required this.event,
    required this.accent,
    required this.index,
  });

  final TourismEvent event;
  final Color accent;
  final int index;

  @override
  Widget build(BuildContext context) {
    final location = formatEventListLocationLine(event);
    final schedule = formatEventScheduleSubtitle(event);
    final venue = event.venue.trim();
    final category = event.eventType.trim();
    final fallback = Container(
      color: accent.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: Icon(Icons.event_rounded, color: accent, size: 28),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.of(context).maybePop().then((_) {
            if (!context.mounted) return;
            openTourismEventDetail(context, event, accentColor: accent);
          });
        },
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: event.imagePath.trim().isEmpty
                        ? fallback
                        : buildMunicipalityImage(
                            event.imagePath,
                            fallback: fallback,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Event $index',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: accent.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.textDark,
                        ),
                      ),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _metaRow(Icons.location_city_rounded, location),
                      ],
                      const SizedBox(height: 3),
                      _metaRow(Icons.schedule_rounded, schedule),
                      if (venue.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _metaRow(Icons.place_outlined, venue),
                      ],
                      if (category.isNotEmpty &&
                          category.toLowerCase() != 'general') ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textGrey.withValues(alpha: 0.85)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.25,
              color: AppColors.textGrey.withValues(alpha: 0.98),
            ),
          ),
        ),
      ],
    );
  }
}
