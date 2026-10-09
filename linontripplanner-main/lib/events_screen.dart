import 'package:flutter/material.dart';
import 'data.dart';
import 'firestore_loader.dart';
import 'widgets/tourism_events_calendar.dart';
import 'widgets/tourism_plan_ui.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    tourismEventsRevision.addListener(_onEventsChanged);
    _load();
  }

  @override
  void dispose() {
    tourismEventsRevision.removeListener(_onEventsChanged);
    super.dispose();
  }

  void _onEventsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await loadEventsFromFirestore();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        title: const Text('Events'),
      ),
      body: TourismPlanPageBody(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    TourismPlanCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TourismPlanUi.sectionHeader(
                            icon: Icons.event_available_rounded,
                            title: 'Event calendar',
                            badge: '${tourismEvents.length}',
                          ),
                          const SizedBox(height: 12),
                          TourismEventsCalendar(
                            events: tourismEvents,
                            titleOnly: true,
                            initialMonth: tourismEvents.isNotEmpty
                                ? tourismEvents.first.dateTime
                                : DateTime.now(),
                            onEventTap: (e) =>
                                openTourismEventDetail(context, e),
                          ),
                          if (tourismEvents.isEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'No events posted yet. The calendar stays available — '
                              'new events will appear on their dates.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: AppColors.textGrey.withValues(alpha: 0.95),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TourismPlanUi.sectionTitleBar(title: 'All events'),
                    const SizedBox(height: 10),
                    TourismEventTitlesList(
                      events: tourismEvents,
                      onEventTap: (e) => openTourismEventDetail(context, e),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
