import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Callable Cloud Functions region (must match `firebase deploy` / Console).
const String kFirebaseFunctionsRegion = 'us-central1';

FirebaseFunctions tourismCloudFunctions() => FirebaseFunctions.instanceFor(
      app: Firebase.app(),
      region: kFirebaseFunctionsRegion,
    );
