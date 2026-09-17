import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/data/landing_lgu_destinations.dart';
import 'package:atmos_trs_system/widgets/atmos_brand_title.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';

/// Viewports at or above this width use the glassmorphism auth layout.
const double kWebGlassAuthBreakpoint = 1024;

/// Default scenic backgrounds for web/desktop glass login + signup slideshow.
/// Same municipality photos as the landing page (all 17 LGUs, landing order).
List<String> get kWebGlassAuthBackgroundSlideshow =>
    landingLguDestinationImagePaths();

/// Full-screen background and overlay for web auth (no text fade-in).
///
/// When [backgroundAssets] has 2+ images (or the default slideshow list is used),
/// backgrounds soft-crossfade on a timer. A single image stays static.
class WebGlassAuthScaffold extends StatefulWidget {
  const WebGlassAuthScaffold({
    super.key,
    required this.child,
    this.backgroundAsset,
    this.backgroundAssets,
    this.maxWidth = 440,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
    this.slideInterval = const Duration(seconds: 5),
    this.crossfadeDuration = const Duration(milliseconds: 900),
  });

  final Widget child;

  /// Single-image override (backward compatible). Ignored when [backgroundAssets]
  /// is non-null and non-empty.
  final String? backgroundAsset;

  /// Explicit slideshow list. When null, uses [kWebGlassAuthBackgroundSlideshow]
  /// unless [backgroundAsset] alone is provided.
  final List<String>? backgroundAssets;

  final double maxWidth;
  final EdgeInsets padding;
  final Duration slideInterval;
  final Duration crossfadeDuration;

  @override
  State<WebGlassAuthScaffold> createState() => _WebGlassAuthScaffoldState();
}

class _WebGlassAuthScaffoldState extends State<WebGlassAuthScaffold> {
  int _index = 0;
  Timer? _timer;
  List<String> _images = const [];

  List<String> _resolveImageList() {
    final explicit = widget.backgroundAssets;
    if (explicit != null && explicit.isNotEmpty) {
      return List<String>.unmodifiable(
        explicit.where((e) => e.trim().isNotEmpty),
      );
    }
    final single = widget.backgroundAsset?.trim();
    if (single != null && single.isNotEmpty) {
      return List<String>.unmodifiable([single]);
    }
    return kWebGlassAuthBackgroundSlideshow;
  }

  @override
  void initState() {
    super.initState();
    _images = _resolveImageList();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant WebGlassAuthScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundAsset != widget.backgroundAsset ||
        oldWidget.backgroundAssets != widget.backgroundAssets ||
        oldWidget.slideInterval != widget.slideInterval) {
      _images = _resolveImageList();
      _index = 0;
      _startTimerIfNeeded();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheAround(_index);
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();
    _timer = null;
    if (_images.length < 2) return;
    _timer = Timer.periodic(widget.slideInterval, (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % _images.length;
      });
      _precacheAround(_index);
    });
  }

  void _precacheAround(int current) {
    if (!mounted || _images.isEmpty) return;
    final next = (current + 1) % _images.length;
    final urls = <String>{
      SupabaseStorageConfig.resolve(_images[current]),
      if (_images.length > 1) SupabaseStorageConfig.resolve(_images[next]),
    };
    for (final url in urls) {
      final provider = (url.startsWith('http://') || url.startsWith('https://'))
          ? NetworkImage(url)
          : AssetImage(url) as ImageProvider;
      unawaited(precacheImage(provider, context));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildBackgroundImage(String assetPath, int? cacheWidth) {
    final resolved = SupabaseStorageConfig.resolve(assetPath);
    final isNetwork =
        resolved.startsWith('http://') || resolved.startsWith('https://');

    Widget fallbackNetwork() => Image.network(
          'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=1600',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: cacheWidth,
          errorBuilder: (_, __, ___) => Container(
            color: AppTheme.brandOrange.withValues(alpha: 0.92),
          ),
        );

    if (isNetwork) {
      return Image.network(
        resolved,
        key: ValueKey<String>(resolved),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cacheWidth,
        errorBuilder: (_, __, ___) => fallbackNetwork(),
      );
    }

    return Image.asset(
      resolved,
      key: ValueKey<String>(resolved),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cacheWidth,
      errorBuilder: (_, __, ___) => fallbackNetwork(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cacheWidth = kIsWeb
        ? (screenWidth * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(640, 1600)
        : null;
    final images = _images.isNotEmpty
        ? _images
        : kWebGlassAuthBackgroundSlideshow;
    final current = images[_index % images.length];

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: widget.crossfadeDuration,
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: SizedBox.expand(
              key: ValueKey<String>('bg-$current'),
              child: _buildBackgroundImage(current, cacheWidth),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.28)),
          Center(
            child: SingleChildScrollView(
              padding: widget.padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted-glass card container for desktop/web auth screens.
class WebGlassAuthCard extends StatelessWidget {
  const WebGlassAuthCard({super.key, required this.child});

  final Widget child;

  static const double radius = 28;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: AppTheme.brandOrange.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class WebGlassBackButton extends StatelessWidget {
  const WebGlassBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.brandOrange,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class WebGlassLogoHeader extends StatelessWidget {
  const WebGlassLogoHeader({
    super.key,
    this.subtitle,
    this.logoSize = 88,
  });

  final String? subtitle;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.95),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.45),
                blurRadius: 28,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: AppTheme.brandOrange.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: TransparentLogo(
                width: logoSize - 20,
                height: logoSize - 20,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        AtmosBrandTitle(
          fontSize: 30,
          letterSpacing: 1.05,
          onDarkSurface: true,
        ),
        const SizedBox(height: 8),
        Text(
          'SMART TOURISM • BETTER EXPERIENCE',
          textAlign: TextAlign.center,
          style: AtmosBrandTypography.meaningTagline(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 14),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

InputDecoration webGlassInputDecoration({
  required String hint,
  IconData? prefixIcon,
  Widget? suffixIcon,
  bool hasFocus = false,
}) {
  const fieldRadius = 16.0;
  final focusGlow = hasFocus
      ? BorderSide(color: AppTheme.brandOrange.withValues(alpha: 0.85), width: 2)
      : BorderSide(color: Colors.white.withValues(alpha: 0.45), width: 1);

  return InputDecoration(
    hintText: hint,
    // Near-white so placeholders stay readable on dark glass fills.
    hintStyle: TextStyle(
      color: Colors.white.withValues(alpha: 0.95),
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    prefixIcon: prefixIcon != null
        ? Container(
            margin: const EdgeInsets.only(left: 8, right: 4),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.brandOrange.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: Icon(prefixIcon, color: Colors.white, size: 18),
          )
        : null,
    prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 48),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.38),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(fieldRadius),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(fieldRadius),
      borderSide: focusGlow,
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(fieldRadius),
      borderSide: BorderSide(color: Colors.red.shade300),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(fieldRadius),
      borderSide: BorderSide(color: Colors.red.shade400, width: 2),
    ),
  );
}

/// Orange primary button with hover elevation for glass auth screens.
class WebGlassPrimaryButton extends StatefulWidget {
  const WebGlassPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.testKey,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Key? testKey;

  @override
  State<WebGlassPrimaryButton> createState() => _WebGlassPrimaryButtonState();
}

class _WebGlassPrimaryButtonState extends State<WebGlassPrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_hovered && enabled ? 1.02 : 1.0),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            key: widget.testKey,
            onPressed: enabled ? widget.onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandOrange,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppTheme.brandOrange.withValues(alpha: 0.55),
              elevation: _hovered && enabled ? 8 : 4,
              shadowColor: AppTheme.brandOrange.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: widget.isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Text field wrapper that tracks focus for glow styling on glass auth screens.
class WebGlassAuthTextField extends StatefulWidget {
  const WebGlassAuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
    this.onEditingComplete,
    this.fieldKey,
    this.autofillHints,
    this.style,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final FocusNode? focusNode;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final VoidCallback? onEditingComplete;
  final Key? fieldKey;
  final Iterable<String>? autofillHints;
  final TextStyle? style;

  @override
  State<WebGlassAuthTextField> createState() => _WebGlassAuthTextFieldState();
}

class _WebGlassAuthTextFieldState extends State<WebGlassAuthTextField> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasFocus = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: hasFocus
            ? [
                BoxShadow(
                  color: AppTheme.brandOrange.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: TextFormField(
        key: widget.fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints ?? const [],
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        onFieldSubmitted: widget.onFieldSubmitted,
        onEditingComplete: widget.onEditingComplete,
        validator: widget.validator,
        style: widget.style ??
            TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 15),
        cursorColor: AppTheme.brandOrange,
        decoration: webGlassInputDecoration(
          hint: widget.hint,
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          hasFocus: hasFocus,
        ),
      ),
    );
  }
}
