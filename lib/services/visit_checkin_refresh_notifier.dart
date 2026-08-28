import 'package:flutter/foundation.dart';

/// Notifies Home (and shell) to refresh after a successful tourist-spot QR check-in.
class VisitCheckInRefreshNotifier extends ChangeNotifier {
  VisitCheckInRefreshNotifier._();

  static final VisitCheckInRefreshNotifier instance =
      VisitCheckInRefreshNotifier._();

  void notifyCheckInCompleted() {
    notifyListeners();
  }
}
