import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// DAE2_Auto sheet: "Monthly Reporting Format for Accommodation Establishment".
class AeDae2SummaryCard extends StatelessWidget {
  const AeDae2SummaryCard({
    super.key,
    required this.report,
    required this.totals,
    required this.readOnly,
    this.issueCount = 0,
    this.busy = false,
    this.onSubmit,
    this.onWithdraw,
  });

  final AeMonthlyReport report;
  final AeMonthTotals totals;
  final bool readOnly;
  final int issueCount;
  final bool busy;
  final VoidCallback? onSubmit;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final items = AeRegisterCalculator.dae2Summary(report, totals);
    final submitted = report.isSubmitted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AeDashTokens.panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Monthly Reporting Format for Accommodation Establishment', style: AeDashTokens.heading(size: 16)),
              const SizedBox(height: 12),
              AeSheetField(label: 'Name of Province / HUC / ICC:', value: report.province),
              AeSheetField(label: 'Name of Municipality / City:', value: report.municipality),
              Wrap(spacing: 16, children: [
                AeSheetField(label: 'Month of', value: AeSheetKit.monthName(report.month), labelWidth: 70, valueWidth: 110),
                AeSheetField(label: 'Year', value: '${report.year}', labelWidth: 40, valueWidth: 70),
                AeSheetField(label: 'Days', value: '${report.days}', labelWidth: 40, valueWidth: 60, valueAlign: TextAlign.right),
              ]),
              const Divider(height: 24),
              for (final i in items) _item(i),
              const SizedBox(height: 10),
              Text('* (1) It is not necessary to disclose the name of the AE in the report if the AE does not want to disclose its name.',
                  style: AeDashTokens.body(size: 11)),
              Text('** (8), (17) and (18) are important business performance indicators.', style: AeDashTokens.body(size: 11)),
              Text('*** When guest arrivals and guest nights are segregated according to residence [(9) to (16)], '
                  'these numbers should be the ones reported and not just the total volume.', style: AeDashTokens.body(size: 11)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AeDashTokens.panelDecoration(
            color: submitted ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),
          ),
          child: Row(
            children: [
              Icon(
                submitted ? Icons.verified_rounded : Icons.pending_actions_rounded,
                color: submitted ? AeDashTokens.success : AeDashTokens.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(submitted ? 'Submitted to LGU' : 'Draft — not yet submitted', style: AeDashTokens.section(size: 14)),
                    Text(
                      submitted
                          ? 'Your LGU tourism office, OPTACA and the Governor can see this month'
                              '${report.lastSignOff == null ? '' : ' (signed by ${report.lastSignOff!.name}, ${report.lastSignOff!.position})'}. '
                              'Later edits need a signature and a reason.'
                          : 'Your LGU sees drafts as "in progress". Submit when the month is complete — '
                              'you will sign with your name and position.'
                              '${issueCount > 0 ? ' Fix $issueCount validation issue(s) first.' : ''}',
                      style: AeDashTokens.body(size: 12),
                    ),
                  ],
                ),
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
                    label: const Text('Submit to LGU'),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _item(AeDae2Item i) {
    final nights = i.label.contains('Nights');
    final fill = i.kpi
        ? AeSheetKit.kpiFill
        : i.input
            ? AeSheetKit.inputFill
            : nights
                ? AeSheetKit.nightsFill.withValues(alpha: 0.85)
                : AeSheetKit.labelFill;
    final bold = i.label.contains('Arrival');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text('(${i.no})', style: AeSheetKit.cell(size: 12.5))),
          Expanded(
            child: Text(
              i.label,
              style: AeSheetKit.cell(
                size: 12.5,
                weight: bold ? FontWeight.w800 : FontWeight.w500,
                italic: i.kpi,
              ),
            ),
          ),
          Container(
            width: 170,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: fill, border: Border.all(color: const Color(0xFF8EA9C1))),
            child: Text(
              i.value.isEmpty ? '—' : i.value,
              textAlign: i.no <= 3 ? TextAlign.center : TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AeSheetKit.cell(size: 12.5, weight: i.kpi || i.no == 1 ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
