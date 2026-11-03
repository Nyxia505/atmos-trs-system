import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/portal_summary_dot_report.dart';
import 'package:atmos_trs_system/widgets/dot_report_form_type_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 420, child: child)),
    );
  }

  DotReportFormTypeDropdown dropdown({
    required List<DotFormCatalogEntry> forms,
    required DotFormCatalogEntry selected,
  }) {
    return DotReportFormTypeDropdown(
      forms: forms,
      selected: selected,
      controller: TextEditingController(text: selected.title),
      onSelected: (_) {},
      primaryColor: const Color(0xFFE87722),
      textDark: const Color(0xFF1C1917),
      textMuted: const Color(0xFF78716C),
      borderColor: const Color(0xFFE7E5E4),
    );
  }

  testWidgets('VAR catalog uses DotReportFormTypeDropdown', (tester) async {
    final forms = kDotFormCatalog;
    await tester.pumpWidget(wrap(dropdown(forms: forms, selected: forms.first)));
    expect(find.byType(DotReportFormTypeDropdown), findsOneWidget);
    expect(find.byType(DropdownMenu<DotFormCatalogEntry>), findsOneWidget);
    expect(find.text('VAR 2 — Visitor Record'), findsWidgets);
  });

  testWidgets('Events catalog uses the same DotReportFormTypeDropdown', (
    tester,
  ) async {
    final forms = PortalSummaryDotReport.eventsForms;
    await tester.pumpWidget(wrap(dropdown(forms: forms, selected: forms.first)));
    expect(find.byType(DotReportFormTypeDropdown), findsOneWidget);
    expect(find.byType(DropdownMenu<DotFormCatalogEntry>), findsOneWidget);
    expect(find.text('EVT 1 — Tourism Events Record'), findsWidgets);
    expect(
      find.text('OPTACA · Scheduled tourism events and activities.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.auto_awesome_outlined), findsWidgets);
    expect(find.byIcon(Icons.event_note_outlined), findsNothing);
  });

  testWidgets('Matrix catalog uses the same DotReportFormTypeDropdown', (
    tester,
  ) async {
    final forms = PortalSummaryDotReport.matrixForms;
    await tester.pumpWidget(wrap(dropdown(forms: forms, selected: forms.first)));
    expect(find.byType(DotReportFormTypeDropdown), findsOneWidget);
    expect(find.byType(DropdownMenu<DotFormCatalogEntry>), findsOneWidget);
    expect(find.text('MFX 1 — Transportation Fare Matrix'), findsWidgets);
  });
}
