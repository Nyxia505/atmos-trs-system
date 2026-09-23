import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:atmos_trs_system/config/supabase_secrets.local.dart';
import 'package:atmos_trs_system/config/supabase_storage_config.dart';

/// Upload credentials for Supabase Storage (AE gallery, etc.).
///
/// Resolution order:
/// 1. `--dart-define` / `--dart-define-from-file`
/// 2. Generated [SupabaseSecretsLocal] from `.env` via `tools/gen_dart_defines.ps1`
///
/// Prefer [anonKey] + Storage RLS on `establishments/*`.
/// [serviceRoleKey] is a local/dev fallback only (same as tools/*.ps1).
abstract final class SupabaseUploadConfig {
  static const String _envAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String _envServiceRoleKey = String.fromEnvironment(
    'SUPABASE_SERVICE_ROLE_KEY',
    defaultValue: '',
  );

  static String get anonKey {
    if (_envAnonKey.trim().isNotEmpty) return _envAnonKey.trim();
    return SupabaseSecretsLocal.anonKey.trim();
  }

  /// Dev/local only. Do not ship production APKs with a real service role.
  static String get serviceRoleKey {
    if (_envServiceRoleKey.trim().isNotEmpty) {
      return _envServiceRoleKey.trim();
    }
    return SupabaseSecretsLocal.serviceRoleKey.trim();
  }

  static String get projectUrl => SupabaseStorageConfig.projectUrl;

  static String get bucket => SupabaseStorageConfig.bucket;

  /// Bearer used for Storage upload/delete.
  static String get uploadBearer {
    if (anonKey.isNotEmpty) return anonKey;
    return serviceRoleKey;
  }

  static bool get hasUploadCredentials => uploadBearer.isNotEmpty;

  @visibleForTesting
  static String describeAuthMode() {
    if (anonKey.isNotEmpty) {
      return _envAnonKey.trim().isNotEmpty ? 'anon_env' : 'anon_local';
    }
    if (serviceRoleKey.isNotEmpty) {
      return _envServiceRoleKey.trim().isNotEmpty
          ? 'service_role_env'
          : 'service_role_local';
    }
    return 'none';
  }

  /// Same as [describeAuthMode] for debug instrumentation outside tests.
  static String authModeLabel() => describeAuthMode();
}
