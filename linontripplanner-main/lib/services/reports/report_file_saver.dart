/// Writes a generated report to wherever the current platform puts downloads.
///
/// On web this triggers a browser download; on desktop it writes to the user's
/// Downloads folder. Both implementations return a short description of where
/// the file landed, for the success notification.
library;

export 'report_file_saver_stub.dart'
    if (dart.library.io) 'report_file_saver_io.dart'
    if (dart.library.js_interop) 'report_file_saver_web.dart';
