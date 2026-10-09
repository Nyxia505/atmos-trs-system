import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data.dart';

/// Visual tokens aligned with TripPlan auth UI (orange + cream).
abstract class AuthDesign {
  static const Color creamBackground = Color(0xFFFFF9F2);
  static const Color inputFill = Color(0xFFFEFBF0);
  static const Color inputBorder = Color(0xFFD9D9D9);
  static const Color placeholder = Color(0xFF999999);
  static const Color secondaryText = Color(0xFF757575);
  static const Color requiredRed = Color(0xFFD93025);
  static const Color stepperLineInactive = Color(0xFFE0E0E0);
  static const double cardRadius = 16;
  static const double fieldRadius = 10;
  /// Max width for login / registration cards (mobile-friendly, centered).
  static const double maxFormWidth = 440;
  static const String loginBackgroundAsset =
      'assets/images/sapang_dalaga_falls.webp';
  /// Frosted panels on top of the login background photo.
  static const double loginSurfaceOpacity = 0.88;
}

/// Scrollable page body with a centered, width-capped column for mobile/tablet.
class AuthCenteredScrollPage extends StatelessWidget {
  final Widget child;

  const AuthCenteredScrollPage({super.key, required this.child});

  static double _horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 12;
    if (w < 600) return 16;
    return 24;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              _horizontalPadding(context),
              16,
              _horizontalPadding(context),
              28,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AuthDesign.maxFormWidth,
                  ),
                  child: ClipRect(
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen photo background for login (with optional dim overlay).
class AuthLoginPhotoBackground extends StatelessWidget {
  final Widget child;

  const AuthLoginPhotoBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Image.asset(
            AuthDesign.loginBackgroundAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.28),
                  Colors.black.withValues(alpha: 0.42),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Orange branding block for login (logo + TripPlan title).
class AuthLoginBrandHeader extends StatelessWidget {
  final double surfaceOpacity;
  final bool fullWidth;

  const AuthLoginBrandHeader({
    super.key,
    this.surfaceOpacity = 1,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        fullWidth ? topInset + 8 : 8,
        16,
        24,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: surfaceOpacity),
        borderRadius: fullWidth
            ? const BorderRadius.vertical(bottom: Radius.circular(24))
            : const BorderRadius.all(Radius.circular(20)),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          left: fullWidth
              ? BorderSide.none
              : BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          right: fullWidth
              ? BorderSide.none
              : BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          top: fullWidth
              ? BorderSide.none
              : BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/images/tripplan.png',
            width: 120,
            height: 120,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(height: 8),
          const Text(
            'TripPlan',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.holidayCalling,
              color: Colors.white,
              fontSize: 43,
              fontWeight: FontWeight.w400,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Misamis Occidental Tourism Trip Planner',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.holidayCalling,
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 23,
              fontWeight: FontWeight.w400,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

/// Login body below full-width header (padded form area).
class AuthLoginFormScroll extends StatelessWidget {
  final Widget child;

  const AuthLoginFormScroll({super.key, required this.child});

  static double _horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 12;
    if (w < 600) return 16;
    return 24;
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              _horizontalPadding(context),
              20,
              _horizontalPadding(context),
              28,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 20),
              child: Align(
                alignment: const Alignment(0, -0.48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AuthDesign.maxFormWidth,
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class RegistrationHeader extends StatelessWidget {
  final int stepOneBased;
  final VoidCallback? onBack;

  const RegistrationHeader({
    super.key,
    required this.stepOneBased,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 22),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: onBack != null
                        ? Material(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: onBack,
                              borderRadius: BorderRadius.circular(10),
                              child: const Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(
                                  Icons.arrow_back_ios_new,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'STEP $stepOneBased',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Registration',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegistrationStepper extends StatelessWidget {
  final int currentIndex;
  final List<String> labels;

  const RegistrationStepper({
    super.key,
    required this.currentIndex,
    this.labels = const [
      'Personal',
      'Travel',
      'Uploads',
    ],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) Expanded(child: _StepConnector(done: currentIndex > i)),
            _StepDot(
              index: i,
              active: currentIndex == i,
              done: currentIndex > i,
              label: labels[i],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool done;

  const _StepConnector({required this.done});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Container(
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: done ? AppColors.primary : AuthDesign.stepperLineInactive,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final bool active;
  final bool done;
  final String label;

  const _StepDot({
    required this.index,
    required this.active,
    required this.done,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final n = index + 1;
    Widget inner;
    if (done) {
      inner = const Icon(Icons.check, color: Colors.white, size: 18);
    } else {
      inner = Text(
        '$n',
        style: TextStyle(
          color: active ? Colors.white : AuthDesign.secondaryText,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      );
    }

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (active || done) ? AppColors.primary : Colors.white,
              border: Border.all(
                color: (active || done)
                    ? AppColors.primary
                    : AuthDesign.stepperLineInactive,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: inner,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppColors.primary : AuthDesign.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class InstructionWithAuthLink extends StatefulWidget {
  final VoidCallback onLoginTap;

  const InstructionWithAuthLink({
    super.key,
    required this.onLoginTap,
  });

  @override
  State<InstructionWithAuthLink> createState() =>
      _InstructionWithAuthLinkState();
}

class _InstructionWithAuthLinkState extends State<InstructionWithAuthLink> {
  late TapGestureRecognizer _loginRecognizer;

  @override
  void initState() {
    super.initState();
    _loginRecognizer = TapGestureRecognizer()..onTap = widget.onLoginTap;
  }

  @override
  void didUpdateWidget(covariant InstructionWithAuthLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onLoginTap != widget.onLoginTap) {
      _loginRecognizer.onTap = widget.onLoginTap;
    }
  }

  @override
  void dispose() {
    _loginRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(
            color: AuthDesign.secondaryText,
            fontSize: 13,
            height: 1.4,
          ),
          children: [
            const TextSpan(
              text:
                  'Please provide accurate and valid details only to help us serve you better. If you already have an account, ',
            ),
            TextSpan(
              text: 'LOG IN',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
              recognizer: _loginRecognizer,
            ),
            const TextSpan(text: ' instead.'),
          ],
        ),
      ),
    );
  }
}

class AuthWhiteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AuthWhiteCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AuthDesign.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AuthFieldLabel extends StatelessWidget {
  final String label;
  final bool required;

  const AuthFieldLabel(this.label, {super.key, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          children: [
            TextSpan(text: label),
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  color: AuthDesign.requiredRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.validator,
    this.maxLines = 1,
    this.textInputAction,
    this.onFieldSubmitted,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      style: const TextStyle(fontSize: 15, color: AppColors.textDark),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(
          color: AuthDesign.placeholder,
          fontSize: 14,
        ),
        filled: true,
        fillColor: AuthDesign.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        prefixIcon: Icon(icon, color: AuthDesign.secondaryText, size: 22),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
          borderSide: const BorderSide(color: AuthDesign.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
          borderSide: const BorderSide(color: AuthDesign.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
          borderSide: const BorderSide(color: AuthDesign.requiredRed),
        ),
      ),
      validator: validator,
    );
  }
}

class AuthDropdownField<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final String hint;
  final IconData icon;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;

  const AuthDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.hint,
    required this.icon,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded,
          color: AuthDesign.secondaryText),
      decoration: InputDecoration(
        filled: true,
        fillColor: AuthDesign.inputFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        prefixIcon: Icon(icon, color: AuthDesign.secondaryText, size: 22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
          borderSide: const BorderSide(color: AuthDesign.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
          borderSide: const BorderSide(color: AuthDesign.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
      hint: Text(
        hint,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AuthDesign.placeholder),
      ),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }
}

/// Side-by-side on wide screens; stacked on narrow phones to avoid overflow.
class AuthResponsivePair extends StatelessWidget {
  final Widget first;
  final Widget second;
  final double breakpoint;

  const AuthResponsivePair({
    super.key,
    required this.first,
    required this.second,
    this.breakpoint = 400,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 12),
              Expanded(child: second),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            const SizedBox(height: 12),
            second,
          ],
        );
      },
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const AuthOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.add, color: AppColors.primary, size: 20),
      label: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.primary, width: 1.2),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

class AuthNavFooter extends StatelessWidget {
  final VoidCallback? onBack;
  final String forwardLabel;
  final VoidCallback? onForward;
  final IconData? forwardIcon;

  const AuthNavFooter({
    super.key,
    this.onBack,
    required this.forwardLabel,
    required this.onForward,
    this.forwardIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
            style: TextButton.styleFrom(
              foregroundColor: AuthDesign.secondaryText,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: onForward,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (forwardIcon != null) ...[
                  Icon(forwardIcon, size: 18),
                  const SizedBox(width: 6),
                ],
                Text(
                  forwardLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular header icon on white cards (person, family, etc.).
class AuthCardHeroIcon extends StatelessWidget {
  final IconData icon;

  const AuthCardHeroIcon({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.12),
      ),
      child: Icon(icon, color: AppColors.primary, size: 32),
    );
  }
}
