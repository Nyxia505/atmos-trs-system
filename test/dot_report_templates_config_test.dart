import 'package:flutter_test/flutter_test.dart';

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';

void main() {
  test('report template public URLs encode spaces', () {
    final url = DotReportType.var2VisitorRecord.publicUrl;
    expect(url, contains('Report%20template'));
    expect(url, contains('VAR%202M%20FORM.xlsx'));
    expect(url.startsWith('https://cgpjqkbbmyxvitwpkikn.supabase.co/'), isTrue);
  });

  test('DAE3B.2 domestic filename maps correctly', () {
    expect(
      DotReportType.dae3b2Domestic.objectFilename,
      'DAE3B.2 - Domestic.xlsx',
    );
    expect(
      DotReportType.dae3b2Domestic.publicUrl,
      contains('DAE3B.2%20-%20Domestic.xlsx'),
    );
  });

  test('bucket public base encodes bucket name', () {
    expect(
      SupabaseReportTemplatesConfig.publicBase,
      'https://cgpjqkbbmyxvitwpkikn.supabase.co/storage/v1/object/public/Report%20template',
    );
  });
}
