import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// Keyboard Enter (main or numpad) runs [onEnter] on steps without text fields,
/// e.g. the Terms & Privacy step's "Continue to registration".
class SignupEnterToContinue extends StatelessWidget {
  const SignupEnterToContinue({
    super.key,
    required this.onEnter,
    required this.child,
  });

  final VoidCallback? onEnter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final action = onEnter;
    if (action == null) return child;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): action,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): action,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// Shared Terms & Data Privacy UI for tourist, LGU, and establishment signup.
class SignupLegalColors {
  const SignupLegalColors._();

  static const Color textDark = Color(0xFF1F2937);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color cardWhite = Colors.white;

  static Color title(bool onDark) => onDark ? Colors.white : textDark;

  static Color body(bool onDark) =>
      onDark ? Colors.white.withValues(alpha: 0.94) : textDark;

  static Color muted(bool onDark) =>
      onDark ? Colors.white.withValues(alpha: 0.82) : textMuted;
}

/// White rounded card matching the tourist signup form card (light mode only).
class SignupLegalCard extends StatelessWidget {
  const SignupLegalCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: SignupLegalColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SignupLegalExpansionCard extends StatefulWidget {
  const SignupLegalExpansionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.expanded,
    required this.reviewed,
    required this.onExpandedChanged,
    required this.bullets,
    this.onDark = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final bool reviewed;
  final ValueChanged<bool> onExpandedChanged;
  final List<String> bullets;
  final bool onDark;

  @override
  State<SignupLegalExpansionCard> createState() =>
      _SignupLegalExpansionCardState();
}

class _SignupLegalExpansionCardState extends State<SignupLegalExpansionCard> {
  final ScrollController _scrollController = ScrollController();

  String get title => widget.title;
  String get subtitle => widget.subtitle;
  IconData get icon => widget.icon;
  bool get expanded => widget.expanded;
  bool get reviewed => widget.reviewed;
  ValueChanged<bool> get onExpandedChanged => widget.onExpandedChanged;
  List<String> get bullets => widget.bullets;
  bool get onDark => widget.onDark;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = reviewed
        ? AppTheme.brandOrange.withValues(alpha: onDark ? 0.7 : 0.45)
        : (onDark
            ? Colors.white.withValues(alpha: 0.2)
            : SignupLegalColors.border);
    final fill = onDark
        ? Colors.white.withValues(alpha: expanded ? 0.1 : 0.06)
        : (expanded ? const Color(0xFFFFF7ED) : const Color(0xFFF9FAFB));
    final muted = SignupLegalColors.muted(onDark);

    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => onExpandedChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: onDark
                        ? Colors.white.withValues(alpha: 0.92)
                        : AppTheme.brandOrange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: SignupLegalColors.title(onDark),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (reviewed) ...[
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: onDark ? Colors.white : AppTheme.brandOrange,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: muted,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: expanded,
                  radius: const Radius.circular(8),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(right: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(
                          height: 1,
                          color: onDark
                              ? Colors.white.withValues(alpha: 0.14)
                              : SignupLegalColors.border,
                        ),
                        const SizedBox(height: 10),
                        ...bullets.map(_bullet),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: SignupLegalColors.muted(onDark),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: SignupLegalColors.body(onDark),
                height: 1.55,
                fontWeight: onDark ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SignupLegalAgreementCard extends StatelessWidget {
  const SignupLegalAgreementCard({
    super.key,
    required this.agreed,
    required this.canAgree,
    required this.onChanged,
    this.onDark = false,
    this.label = 'I have read and agree to the Terms and Conditions '
        'and the Data Privacy Policy (RA 10173) of ATMOS-TRS.',
  });

  final bool agreed;
  final bool canAgree;
  final ValueChanged<bool>? onChanged;
  final bool onDark;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fill = onDark
        ? (agreed
            ? AppTheme.brandOrange.withValues(alpha: 0.3)
            : Colors.black.withValues(alpha: 0.44))
        : (agreed
            ? AppTheme.brandOrange.withValues(alpha: 0.07)
            : SignupLegalColors.cardWhite);
    final idleBorder =
        onDark ? Colors.white.withValues(alpha: 0.22) : SignupLegalColors.border;
    final enabled = canAgree && onChanged != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!canAgree)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Open both sections above, then you can agree.',
              style: TextStyle(
                fontSize: 12.5,
                color: SignupLegalColors.muted(onDark),
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: agreed ? AppTheme.brandOrange : idleBorder,
              width: agreed ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => onChanged!(!agreed) : null,
            child: Opacity(
              opacity: canAgree ? 1 : 0.5,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color:
                            agreed ? AppTheme.brandOrange : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: agreed
                              ? AppTheme.brandOrange
                              : (onDark
                                  ? Colors.white.withValues(alpha: 0.45)
                                  : SignupLegalColors.border),
                          width: 2,
                        ),
                      ),
                      child: agreed
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: SignupLegalColors.body(onDark),
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
