import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:flutter/material.dart';

/// Target phone width for the tourist dashboard in desktop browsers.
const double kTouristWebMobileWidth = 430;

/// Provides the live shell widget tree into the nested [Navigator] route so
/// tab switches rebuild instead of freezing the first frame forever.
class _TouristShellScope extends InheritedWidget {
  const _TouristShellScope({
    required this.shell,
    required super.child,
  });

  final Widget shell;

  static Widget watch(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_TouristShellScope>();
    assert(scope != null, 'TouristWebMobileFrame is missing _TouristShellScope');
    return scope!.shell;
  }

  @override
  bool updateShouldNotify(_TouristShellScope oldWidget) =>
      shell != oldWidget.shell;
}

/// Wraps the tourist shell on web: branded backdrop + centered phone frame.
///
/// [bottomBar] stays *outside* the nested [Navigator] so Home/Explore/Scan/
/// Notification/Account taps always hit Flutter and update immediately.
/// The nested navigator exists only so dialogs/sheets stay inside the frame.
class TouristWebMobileFrame extends StatelessWidget {
  const TouristWebMobileFrame({
    super.key,
    required this.child,
    this.bottomBar,
  });

  final Widget child;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final frameWidth =
        size.width < kTouristWebMobileWidth ? size.width : kTouristWebMobileWidth;
    final frameSize = Size(frameWidth, size.height);
    final bgUrl =
        SupabaseStorageConfig.resolve(MisamisOccidentalImages.landingBg);
    final ImageProvider bgImage = bgUrl.startsWith('http')
        ? NetworkImage(bgUrl)
        : AssetImage(MisamisOccidentalImages.landingBg);

    final phone = Material(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ClipRect(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(size: frameSize),
          child: _TouristShellScope(
            shell: child,
            child: Column(
              children: [
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute<void>(
                        settings: const RouteSettings(name: 'tourist-web-shell'),
                        builder: (routeContext) {
                          // Depend on InheritedWidget so tab changes rebuild.
                          return _TouristShellScope.watch(routeContext);
                        },
                      );
                    },
                  ),
                ),
                if (bottomBar != null) bottomBar!,
              ],
            ),
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: bgImage,
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.18),
                  BlendMode.darken,
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.brandOrange.withValues(alpha: 0.42),
                  AppTheme.gradientDarkBlue.withValues(alpha: 0.62),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: SizedBox(
            width: frameWidth,
            height: size.height,
            child: phone,
          ),
        ),
      ],
    );
  }
}

/// Keeps alert dialogs inside the tourist web phone frame.
Future<T?> showTouristDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  RouteSettings? routeSettings,
}) {
  return showDialog<T>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    builder: builder,
  );
}
