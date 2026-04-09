import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// One-time welcome for new visitors on the landing page.
/// On web: strongly encourages installing the mobile app (QR scan, GPS check-in).
/// On native: short friendly welcome without store links.
Future<void> showNewUserWelcomeDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.waving_hand_rounded,
                        color: Color(0xFFF97316),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kIsWeb
                                ? 'Welcome to ATMOS TRS!'
                                : 'Welcome!',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Maayong pag-abot! We're glad you're here.",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (kIsWeb) ...[
                  Text(
                    'For the full experience — scan LGU & spot QR codes, check in with GPS, '
                    'and carry your digital tourist ID — download the ATMOS TRS app on your phone.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFF97316).withOpacity(0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.phone_android_rounded, color: Colors.orange.shade800, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Browsing here is great to explore; the mobile app is built for on-site QR scanning and LGU check-ins.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                            disabledBackgroundColor: const Color(0xFF334155),
                            disabledForegroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.android_rounded, size: 20),
                          label: _storeComingSoonLabel('Google Play'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                            disabledBackgroundColor: const Color(0xFF334155),
                            disabledForegroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.apple, size: 20),
                          label: _storeComingSoonLabel('App Store'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    "You're in the ATMOS TRS app. Register or sign in to get your tourist QR, "
                    'scan codes at destinations, and check in at LGUs across Misamis Occidental.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    kIsWeb ? 'Continue on website' : 'Let’s go',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFFF97316),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _storeComingSoonLabel(String storeName) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        storeName,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      Text(
        'Coming soon',
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 11,
          color: Colors.white.withOpacity(0.85),
        ),
      ),
    ],
  );
}
