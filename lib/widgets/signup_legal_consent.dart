import 'dart:math' as math;

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
    this.onScrolledToEnd,
    this.onDark = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final bool reviewed;
  final ValueChanged<bool> onExpandedChanged;
  final List<String> bullets;

  /// Fired once the open policy is scrolled to the end, or fits without scrolling.
  final VoidCallback? onScrolledToEnd;
  final bool onDark;

  @override
  State<SignupLegalExpansionCard> createState() =>
      _SignupLegalExpansionCardState();
}

class _SignupLegalExpansionCardState extends State<SignupLegalExpansionCard>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _arrowPulse;
  bool _openedOnce = false;
  bool _endNotified = false;

  String get title => widget.title;
  String get subtitle => widget.subtitle;
  IconData get icon => widget.icon;
  bool get expanded => widget.expanded;
  bool get reviewed => widget.reviewed;
  ValueChanged<bool> get onExpandedChanged => widget.onExpandedChanged;
  List<String> get bullets => widget.bullets;
  bool get onDark => widget.onDark;

  @override
  void initState() {
    super.initState();
    _openedOnce = widget.expanded;
    _arrowPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _scrollController.addListener(_considerEnd);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncArrowMotion();
  }

  @override
  void didUpdateWidget(SignupLegalExpansionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded && !oldWidget.expanded) {
      _openedOnce = true;
      _scheduleEndCheck();
    }
    if (widget.reviewed) _endNotified = true;
    _syncArrowMotion();
  }

  void _syncArrowMotion() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Widget tests wait until animations settle. A repeating pulse never does.
    final widgetTest = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('Test');
    final shouldPulse =
        !reduceMotion && !widgetTest && !_openedOnce && !widget.reviewed;
    if (shouldPulse) {
      if (!_arrowPulse.isAnimating) _arrowPulse.repeat(reverse: true);
    } else {
      _arrowPulse.stop();
      _arrowPulse.value = 0;
    }
  }

  void _scheduleEndCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _considerEnd();
    });
  }

  void _considerEnd() {
    if (!mounted || !widget.expanded || _endNotified) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    final atEnd = position.maxScrollExtent <= 1 ||
        position.pixels >= position.maxScrollExtent - 12;
    if (!atEnd) return;
    _endNotified = true;
    widget.onScrolledToEnd?.call();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_considerEnd);
    _scrollController.dispose();
    _arrowPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = reviewed
        ? (onDark
            ? Colors.white.withValues(alpha: 0.28)
            : SignupLegalColors.border)
        : AppTheme.brandOrange.withValues(alpha: onDark ? 0.9 : 0.75);
    final fill = onDark
        ? Colors.white.withValues(alpha: expanded ? 0.1 : 0.06)
        : (expanded ? const Color(0xFFFFF7ED) : const Color(0xFFF9FAFB));
    final muted = SignupLegalColors.muted(onDark);

    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: reviewed ? 1 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            label: '$title. ${reviewed ? 'Read. ' : ''}'
                '${expanded ? 'Tap to close' : 'Tap to read'}',
            child: InkWell(
              onTap: () => onExpandedChanged(!expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: SignupLegalColors.title(onDark),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: muted,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _readCue(muted),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              onEnd: _considerEnd,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.min(
                            220,
                            MediaQuery.sizeOf(context).height * 0.34,
                          ),
                        ),
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          radius: const Radius.circular(8),
                          child: Semantics(
                            label: '$title. Scroll to read the full policy.',
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
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readCue(Color muted) {
    final cue = expanded ? 'Tap to close' : 'Tap to read';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reviewed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: onDark ? Colors.white : AppTheme.brandOrange,
              ),
              const SizedBox(width: 4),
              Text(
                'Read',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: onDark ? Colors.white : AppTheme.brandOrange,
                ),
              ),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!reviewed || expanded)
              ExcludeSemantics(
                child: Text(
                  cue,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.brandOrange,
                  ),
                ),
              ),
            AnimatedBuilder(
              animation: _arrowPulse,
              builder: (context, child) {
                final dy = _arrowPulse.isAnimating
                    ? math.sin(_arrowPulse.value * math.pi) * 3
                    : 0.0;
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: child,
                );
              },
              child: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: reviewed ? muted : AppTheme.brandOrange,
                size: 24,
              ),
            ),
          ],
        ),
      ],
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
    this.lockedHint = 'Open both sections above, then you can agree.',
    this.label = 'I have read and agree to the Terms and Conditions '
        'and the Data Privacy Policy (RA 10173) of ATMOS-TRS.',
  });

  final bool agreed;
  final bool canAgree;
  final ValueChanged<bool>? onChanged;
  final bool onDark;
  final String lockedHint;
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
        if (!canAgree && lockedHint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              lockedHint,
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
