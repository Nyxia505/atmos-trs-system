import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show FontWeight;
import 'package:google_fonts/google_fonts.dart';

/// Preloads brand fonts before the first frame to avoid ATMOS-TRS text flash (FOUT).
Future<void> preloadAtmosBrandFonts() async {
  try {
    await GoogleFonts.pendingFonts([
      GoogleFonts.montserrat(fontWeight: FontWeight.w500),
      GoogleFonts.montserrat(fontWeight: FontWeight.w600),
      GoogleFonts.montserrat(fontWeight: FontWeight.w800),
    ]);
  } catch (e) {
    debugPrint('Atmos font preload skipped: $e');
  }
}
