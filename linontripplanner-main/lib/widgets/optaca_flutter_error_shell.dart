import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Replaces Flutter's blank white [ErrorWidget] (web release) and swallows
/// uncaught async errors so a single module failure cannot blank the portal.
void installVisibleFlutterErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async: $error\n$stack');
    return true;
  };

  ErrorWidget.builder = (details) {
    return Material(
      color: const Color(0xFFFFF7ED),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFEA580C),
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This page hit an error',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details.exceptionAsString(),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use the sidebar to open another module, or retry this page.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };
}
