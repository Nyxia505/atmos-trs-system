import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/utils/mice_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// CUS summary for a period: totals, M-I-C-E category breakdown, foreign
/// countries and (month view) the submit / back-to-draft action.
class MiceSummaryCard extends StatelessWidget {
  const MiceSummaryCard({
    super.key,
    required this.totals,
    required this.periodLabel,
    required this.venueName,
    required this.municipality,
    required this.readOnly,
    this.report,
    this.issueCount = 0,
    this.busy = false,
    this.monthsInPeriod = 1,
    this.submittedMonths = 0,
    this.onSubmit,
    this.onWithdraw,
  });

  final MiceMonthTotals totals;
  final String periodLabel;
  final String venueName;
  final String municipality;
  final bool readOnly;

  /// Month view only (null for quarter / year roll-ups).
  final MiceMonthlyReport? report;
  final int issueCount;
  final bool busy;
  final int monthsInPeriod;
  final int submittedMonths;
  final VoidCallback? onSubmit;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final t = totals;
    String pct(int part) => t.attendees == 0 ? '-' : '${(part * 100 / t.attendees).round()}%';
    final kpis = <(String, String, String, IconData, Color)>[
      ('Events', '${t.events}', t.multiDayEvents > 0 ? '${t.multiDayEvents} multi-day' : '', Icons.event_rounded, AeDashTokens.accent),
      ('Hours', MiceRegisterCalculator.hoursLabel(t.hours), t.events == 0 ? '' : '${MiceRegisterCalculator.hoursLabel(t.hours / t.events)} avg / event', Icons.schedule_rounded, AeDashTokens.chartSecondary),
      ('Attendees', '${t.attendees}', t.events == 0 ? '' : '${(t.attendees / t.events).round()} avg / event', Icons.groups_rounded, AeDashTokens.success),
      ('Local · Foreign', '${t.local} · ${t.foreign}', 'foreign ${pct(t.foreign)}', Icons.public_rounded, AeDashTokens.info),
      ('Male · Female', '${t.male} · ${t.female}', 'female ${pct(t.female)}', Icons.wc_rounded, AeDashTokens.chartTertiary),
      ('Exhibits', '${t.exhibitions}', t.exhibitions == 0 ? '' : '${t.exhibitors} exhibitors · ${t.exhibitVisitors} visitors', Icons.storefront_rounded, AeDashTokens.warning),
    ];
    final cats = MiceRegisterCalculator.categoryBreakdown(t);
    final countries = t.byCountry.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AeDashTokens.panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MICE Utilization Summary', style: AeDashTokens.heading(size: 16)),
              const SizedBox(height: 10),
              AeSheetField(label: 'Name of establishment:', value: venueName),
              AeSheetField(label: 'City / Municipality:', value: municipality),
              AeSheetField(label: 'Period:', value: periodLabel),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final k in kpis)
                  Container(
                    width: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: k.$5.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: k.$5.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Icon(k.$4, color: k.$5, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(k.$1, style: AeDashTokens.body(size: 11)),
                          Text(k.$2, style: AeDashTokens.number(size: 17)),
                          if (k.$3.isNotEmpty) Text(k.$3, style: AeDashTokens.body(size: 10.5)),
                        ]),
                      ),
                    ]),
                  ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AeDashTokens.panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('By event category', style: AeDashTokens.section(size: 14)),
              const SizedBox(height: 8),
              if (cats.isEmpty)
                Text('No events in this period.', style: AeDashTokens.body(size: 12.5))
              else
                for (final (c, ct) in cats)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Icon(c.icon, size: 18, color: AeDashTokens.accent),
                      const SizedBox(width: 8),
                      SizedBox(width: 190, child: Text(c.label, style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: t.attendees == 0 ? 0 : ct.attendees / t.attendees,
                            minHeight: 8,
                            backgroundColor: AeDashTokens.mutedSurface,
                            color: AeDashTokens.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 190,
                        child: Text(
                          '${ct.events} event(s) · ${ct.attendees} pax · ${MiceRegisterCalculator.hoursLabel(ct.hours)} h',
                          textAlign: TextAlign.right,
                          style: AeDashTokens.body(size: 12),
                        ),
                      ),
                    ]),
                  ),
              if (countries.isNotEmpty) ...[
                const Divider(height: 24),
                Text('Foreign attendees by country (optional breakdown)', style: AeDashTokens.section(size: 14)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in countries.take(20)) Chip(label: Text('${e.key} · ${e.value}')),
                ]),
                if (t.byCountry.values.fold<int>(0, (a, b) => a + b) < t.foreign)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${t.foreign - t.byCountry.values.fold<int>(0, (a, b) => a + b)} foreign attendee(s) without a country.',
                      style: AeDashTokens.body(size: 11.5),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (report != null) _statusPanel(report!) else _rollupStatus(),
      ],
    );
  }

  Widget _rollupStatus() => Container(
        padding: const EdgeInsets.all(16),
        decoration: AeDashTokens.panelDecoration(),
        child: Row(children: [
          const Icon(Icons.fact_check_rounded, color: AeDashTokens.info),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$submittedMonths of $monthsInPeriod month(s) submitted to LGU in this period. '
              'Open a month to add events or submit it.',
              style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text),
            ),
          ),
        ]),
      );

  Widget _statusPanel(MiceMonthlyReport r) {
    final submitted = r.isSubmitted;
    final empty = totals.events == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AeDashTokens.panelDecoration(
        color: submitted ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),
      ),
      child: Row(children: [
        Icon(
          submitted ? Icons.verified_rounded : Icons.pending_actions_rounded,
          color: submitted ? AeDashTokens.success : AeDashTokens.accent,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              submitted ? (empty ? 'Submitted — no events this month' : 'Submitted to LGU') : 'Draft — not yet submitted',
              style: AeDashTokens.section(size: 14),
            ),
            Text(
              submitted
                  ? 'Your LGU tourism office, OPTACA and the Governor see this month on the CUS MICE report'
                      '${r.lastSignOff == null ? '' : ' (signed by ${r.lastSignOff!.name}, ${r.lastSignOff!.position})'}. '
                      'Later edits need a signature and a reason.'
                  : empty
                      ? 'No events this month? Submit it anyway so your LGU knows the venue reported (nil report).'
                      : 'Submit when the month is complete — you will sign with your name and position.'
                          '${issueCount > 0 ? ' Fix $issueCount event(s) with errors first.' : ''}',
              style: AeDashTokens.body(size: 12),
            ),
          ]),
        ),
        if (!readOnly) ...[
          const SizedBox(width: 12),
          if (busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else if (submitted)
            OutlinedButton(onPressed: onWithdraw, child: const Text('Back to draft'))
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AeDashTokens.accent),
              onPressed: issueCount > 0 ? null : onSubmit,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(empty ? 'Submit "no events"' : 'Submit to LGU'),
            ),
        ],
      ]),
    );
  }
}
