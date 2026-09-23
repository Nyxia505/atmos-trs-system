/// Public Supabase Storage config for official DOT / DAE report templates.
///
/// Templates live in the public bucket [bucket] (do not upload Excel into Cursor).
/// Local reference copies live under `forms_format/` (see [DotFormCatalogEntry.localFilename]).
abstract final class SupabaseReportTemplatesConfig {
  static const String projectUrl =
      'https://cgpjqkbbmyxvitwpkikn.supabase.co';

  /// Bucket name as shown in Supabase Storage (includes a space).
  static const String bucket = 'Report template';

  static String get publicBase {
    final encodedBucket = Uri.encodeComponent(bucket);
    return '$projectUrl/storage/v1/object/public/$encodedBucket';
  }

  /// Build a public object URL with path-segment encoding (spaces → %20).
  static String publicUrlForObjectKey(String objectKey) {
    final encoded = objectKey
        .trim()
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return '$publicBase/$encoded';
  }
}

/// High-level form family for grouping / search filters.
enum DotFormCategory {
  attraction,
  accommodation,
  mice,
}

extension DotFormCategoryX on DotFormCategory {
  String get label => switch (this) {
        DotFormCategory.attraction => 'Attraction (VAR)',
        DotFormCategory.accommodation => 'Accommodation (DAE)',
        DotFormCategory.mice => 'Events (MICE)',
      };
}

/// How ATMOS produces this form today.
enum DotFormFillMode {
  /// Official sheet cells filled from QR check-ins + profiles where mapped.
  atmosFill,
  /// ATMOS-built workbook / best-effort rows + gaps (not a blank happy path).
  /// Official empty template remains a secondary download only.
  atmosDerived,
}

/// Fillable / derived DOT exports (auto-report + fill pipeline).
enum DotReportType {
  var2VisitorRecord,
  var4DomesticTravelers,
  var5InternationalVisitors,
  dae3FormA,
  dae3b2Domestic,
  dae3bFormAInternational,
}

extension DotReportTypeX on DotReportType {
  String get id => switch (this) {
        DotReportType.var2VisitorRecord => 'var2',
        DotReportType.var4DomesticTravelers => 'var4',
        DotReportType.var5InternationalVisitors => 'var5',
        DotReportType.dae3FormA => 'dae3',
        DotReportType.dae3b2Domestic => 'dae3b2_domestic',
        DotReportType.dae3bFormAInternational => 'dae3b_form_a_intl',
      };

  String get title => catalogEntry.title;

  String get subtitle => catalogEntry.subtitle;

  String get objectFilename => catalogEntry.objectFilename;

  String get publicUrl => catalogEntry.publicUrl;

  bool get supportsAtmosFill =>
      catalogEntry.fillMode == DotFormFillMode.atmosFill ||
      catalogEntry.fillMode == DotFormFillMode.atmosDerived;

  DotFormCatalogEntry get catalogEntry =>
      kDotFormCatalogById[id] ?? kDotFormCatalogById['var2']!;
}

/// Unified catalog entry for LGU / super-admin Analytics form picker.
class DotFormCatalogEntry {
  const DotFormCatalogEntry({
    required this.id,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.fillMode,
    required this.objectFilename,
    required this.localFilename,
    required this.searchTags,
    this.reportType,
  });

  final String id;
  final String code;
  final String title;
  final String subtitle;
  final DotFormCategory category;
  final DotFormFillMode fillMode;

  /// Exact object key in the Supabase bucket.
  final String objectFilename;

  /// Filename under repo `forms_format/` (reference copy).
  final String localFilename;

  final List<String> searchTags;

  /// Non-null when ATMOS can fill this form.
  final DotReportType? reportType;

  String get publicUrl =>
      SupabaseReportTemplatesConfig.publicUrlForObjectKey(objectFilename);

  String get displayLabel => '$code — ${title.replaceFirst(RegExp(r'^[^—]+—\s*'), '')}';

  String get capabilityLabel => switch (fillMode) {
        DotFormFillMode.atmosFill => 'ATMOS fill',
        DotFormFillMode.atmosDerived => 'Best-effort + gaps',
      };

  bool get supportsAtmosFill =>
      fillMode == DotFormFillMode.atmosFill ||
      fillMode == DotFormFillMode.atmosDerived;

  /// Official empty template is secondary — never the primary Analytics CTA.
  bool get offersOfficialBlankSecondary => true;

  bool matchesSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      id,
      code,
      title,
      subtitle,
      category.label,
      capabilityLabel,
      objectFilename,
      localFilename,
      ...searchTags,
    ].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every((part) => hay.contains(part));
  }
}

/// All 11 official templates (forms_format + Supabase bucket keys).
const List<DotFormCatalogEntry> kDotFormCatalog = [
  DotFormCatalogEntry(
    id: 'var2',
    code: 'VAR 2',
    title: 'VAR 2 — Visitor Record',
    subtitle: 'Fills official VAR 2 from QR check-ins + tourist profiles',
    category: DotFormCategory.attraction,
    fillMode: DotFormFillMode.atmosFill,
    objectFilename: 'VAR 2M FORM.xlsx',
    localFilename: 'VAR-2M-FORM.xlsx',
    searchTags: [
      'visitor',
      'attraction',
      'var2',
      'var 2m',
      'tourism attraction visitor record',
    ],
    reportType: DotReportType.var2VisitorRecord,
  ),
  DotFormCatalogEntry(
    id: 'var4',
    code: 'VAR 4',
    title: 'VAR 4 — Domestic Travelers',
    subtitle:
        'Best-effort fill — domestic visits by PH origin from check-in profiles',
    category: DotFormCategory.attraction,
    fillMode: DotFormFillMode.atmosDerived,
    objectFilename: 'VAR 4.DOMESTIC TRAVELERS.xlsx',
    localFilename: 'VAR-4.DOMESTIC-TRAVELERS.xlsx',
    searchTags: [
      'domestic',
      'day visitors',
      'regional distribution',
      'attraction',
      'origin',
    ],
    reportType: DotReportType.var4DomesticTravelers,
  ),
  DotFormCatalogEntry(
    id: 'var5',
    code: 'VAR 5',
    title: 'VAR 5 — International Visitors',
    subtitle:
        'Best-effort fill — international visits by country from profiles',
    category: DotFormCategory.attraction,
    fillMode: DotFormFillMode.atmosDerived,
    objectFilename: 'VAR 5.INTERNATIONAL VISITORS.xlsx',
    localFilename: 'VAR-5.INTERNATIONAL-VISITORS.xlsx',
    searchTags: [
      'international',
      'foreign',
      'country',
      'form a',
      'attraction',
    ],
    reportType: DotReportType.var5InternationalVisitors,
  ),
  DotFormCatalogEntry(
    id: 'dae3',
    code: 'DAE-3',
    title: 'DAE-3 — Municipal AE Monthly',
    subtitle: 'Fills DAE-3 from confirmed AE stays (nights/rooms when staff enter them)',
    category: DotFormCategory.accommodation,
    fillMode: DotFormFillMode.atmosFill,
    objectFilename: 'DAE-3 FORM.xlsx',
    localFilename: 'DAE-3-FORM.xlsx',
    searchTags: [
      'dae3',
      'form a',
      'ae',
      'accommodation',
      'monthly',
      'guest check-in',
    ],
    reportType: DotReportType.dae3FormA,
  ),
  DotFormCatalogEntry(
    id: 'dae3b2_domestic',
    code: 'DAE 3B.2',
    title: 'DAE 3B.2 — Domestic Origins',
    subtitle: 'Fills domestic origin × month from check-in profiles',
    category: DotFormCategory.accommodation,
    fillMode: DotFormFillMode.atmosFill,
    objectFilename: 'DAE3B.2 - Domestic.xlsx',
    localFilename: 'DAE3B.2-Domestic.xlsx',
    searchTags: [
      'dae3b',
      'domestic',
      'overnight',
      'region',
      'province',
      'city',
      'origin',
    ],
    reportType: DotReportType.dae3b2Domestic,
  ),
  DotFormCatalogEntry(
    id: 'dae3b_form_a_intl',
    code: 'DAE3 Form A',
    title: 'DAE3 Form A — International',
    subtitle:
        'Best-effort — foreign visits by country (AE stays when confirmed)',
    category: DotFormCategory.accommodation,
    fillMode: DotFormFillMode.atmosDerived,
    objectFilename: 'DAE3B_FORM_A - International.xlsx',
    localFilename: 'DAE3B_FORM_A-International.xlsx',
    searchTags: [
      'international',
      'country',
      'form a',
      'ae',
      'foreign',
    ],
    reportType: DotReportType.dae3bFormAInternational,
  ),
  DotFormCatalogEntry(
    id: 'dae1b2',
    code: 'DAE 1B.2',
    title: 'DAE 1B.2 — AE Fill-up',
    subtitle:
        'Best-effort + gaps — needs confirmed establishment stays for overnight',
    category: DotFormCategory.accommodation,
    fillMode: DotFormFillMode.atmosDerived,
    objectFilename: '3. DAE1B.2.xlsx',
    localFilename: '3.-DAE1B.2.xlsx',
    searchTags: [
      'dae1b',
      '1b.2',
      'overnight',
      'domestic',
      'ae fill-up',
      'daily',
    ],
  ),
  DotFormCatalogEntry(
    id: 'dae1b2_domestic',
    code: 'DAE 1B.2 Dom',
    title: 'DAE 1B.2 — Domestic (Daily / AE / Monthly)',
    subtitle:
        'Best-effort + gaps — domestic overnight matrix awaits AE stay QR',
    category: DotFormCategory.accommodation,
    fillMode: DotFormFillMode.atmosDerived,
    objectFilename: 'DAE1B.2.Domestic.xlsx',
    localFilename: 'DAE1B.2.Domestic.xlsx',
    searchTags: [
      'dae1b',
      'domestic',
      'overnight',
      'daily',
      'monthly',
      'ae',
    ],
  ),
  DotFormCatalogEntry(
    id: 'dae1b_macro',
    code: 'DAE-1B',
    title: 'DOT ET DAE1B — Macro Register',
    subtitle:
        'Best-effort + gaps — guest register needs establishment confirmation',
    category: DotFormCategory.accommodation,
    fillMode: DotFormFillMode.atmosDerived,
    objectFilename: '1. DOT_ET_DAE1Bv10c.xlsm',
    localFilename: '1.-DOT_ET_DAE1Bv10c.xlsm',
    searchTags: [
      'dae1b',
      'macro',
      'xlsm',
      'daily record',
      'occupancy',
      'check-in',
    ],
  ),
  DotFormCatalogEntry(
    id: 'dae1a_manual',
    code: 'DAE-1A',
    title: 'DAE-1A — Manual Tally',
    subtitle:
        'Best-effort + gaps — rooms/guest nights from staff-confirmed stays',
    category: DotFormCategory.accommodation,
    fillMode: DotFormFillMode.atmosDerived,
    objectFilename: '2.DAE1A_Manual.xls',
    localFilename: '2.DAE1A_Manual.xls',
    searchTags: [
      'dae1a',
      'manual',
      'xls',
      'rooms',
      'guest nights',
      'sme',
    ],
  ),
  DotFormCatalogEntry(
    id: 'mice_cus',
    code: 'CUS MICE',
    title: 'CUS — MICE Utilization Survey',
    subtitle: 'Best-effort + gaps — MICE utilization from event data when present',
    category: DotFormCategory.mice,
    fillMode: DotFormFillMode.atmosDerived,
    objectFilename: 'CUS-FORM-MICE-UTILIZATION-SURVEY-FORM.xlsx',
    localFilename: 'CUS-FORM-MICE-UTILIZATION-SURVEY-FORM.xlsx',
    searchTags: [
      'mice',
      'cus',
      'event',
      'conference',
      'exhibition',
      'survey',
    ],
  ),
];

final Map<String, DotFormCatalogEntry> kDotFormCatalogById = {
  for (final e in kDotFormCatalog) e.id: e,
};

/// @Deprecated — use [kDotFormCatalog] blank-only entries.
class DotBlankTemplate {
  const DotBlankTemplate({
    required this.title,
    required this.objectFilename,
  });

  final String title;
  final String objectFilename;

  String get publicUrl =>
      SupabaseReportTemplatesConfig.publicUrlForObjectKey(objectFilename);
}

/// @Deprecated — prefer secondary official-blank from [kDotFormCatalog].
final List<DotBlankTemplate> kDotBlankTemplates = [
  for (final e in kDotFormCatalog)
    DotBlankTemplate(title: e.title, objectFilename: e.objectFilename),
];
