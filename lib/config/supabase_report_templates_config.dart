/// Public Supabase Storage config for official DOT / DAE report templates.
///
/// Templates live in the public bucket [bucket] (do not upload Excel into Cursor).
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

/// High-priority DOT exports we fill with ATMOS data when possible.
enum DotReportType {
  var2VisitorRecord,
  dae3FormA,
  dae3b2Domestic,
}

extension DotReportTypeX on DotReportType {
  String get id => switch (this) {
        DotReportType.var2VisitorRecord => 'var2',
        DotReportType.dae3FormA => 'dae3_form_a',
        DotReportType.dae3b2Domestic => 'dae3b2_domestic',
      };

  String get title => switch (this) {
        DotReportType.var2VisitorRecord => 'VAR 2 — Visitor Record',
        DotReportType.dae3FormA => 'DAE-3 Form A',
        DotReportType.dae3b2Domestic => 'DAE 3B.2 Domestic',
      };

  String get subtitle => switch (this) {
        DotReportType.var2VisitorRecord =>
          'Fills official VAR 2 from QR check-ins + tourist profiles',
        DotReportType.dae3FormA =>
          'Fills DAE-3 guest counts from check-ins (nights/rooms blank)',
        DotReportType.dae3b2Domestic =>
          'Fills domestic origin × month from check-in profiles',
      };

  /// Exact object key in the Supabase bucket.
  String get objectFilename => switch (this) {
        DotReportType.var2VisitorRecord => 'VAR 2M FORM.xlsx',
        DotReportType.dae3FormA => 'DAE-3 FORM.xlsx',
        DotReportType.dae3b2Domestic => 'DAE3B.2 - Domestic.xlsx',
      };

  String get publicUrl =>
      SupabaseReportTemplatesConfig.publicUrlForObjectKey(objectFilename);

  /// Whether we attempt to append ATMOS data sheets (xlsx only).
  bool get supportsAtmosFill => objectFilename.toLowerCase().endsWith('.xlsx');
}

/// Other official templates available as blank downloads (no ATMOS fill yet).
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

const List<DotBlankTemplate> kDotBlankTemplates = [
  DotBlankTemplate(
    title: 'VAR 2M FORM (alternate)',
    objectFilename: 'VAR 2M FORM (1).xlsx',
  ),
  DotBlankTemplate(
    title: 'DAE3B Form A — International',
    objectFilename: 'DAE3B_FORM_A - International.xlsx',
  ),
  DotBlankTemplate(
    title: 'DAE 1B.2',
    objectFilename: '3. DAE1B.2.xlsx',
  ),
  DotBlankTemplate(
    title: 'DAE 1B.2 Domestic',
    objectFilename: 'DAE1B.2.Domestic.xlsx',
  ),
  DotBlankTemplate(
    title: 'VAR 4 Domestic Travelers',
    objectFilename: 'VAR 4.DOMESTIC TRAVELERS.xlsx',
  ),
  DotBlankTemplate(
    title: 'VAR 5 International Visitors',
    objectFilename: 'VAR 5.INTERNATIONAL VISITORS.xlsx',
  ),
  DotBlankTemplate(
    title: 'DOT ET DAE1B (macro)',
    objectFilename: '1. DOT_ET_DAE1Bv10c.xlsm',
  ),
  DotBlankTemplate(
    title: 'DAE1A Manual (.xls)',
    objectFilename: '2.DAE1A_Manual.xls',
  ),
];
