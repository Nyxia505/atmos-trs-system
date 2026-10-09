import 'package:flutter/material.dart';

const String _kFromLoginArg = 'fromLogin';
const String _kLoginDepthArg = 'loginDepth';

/// Horizontal shared-axis transition between the login and signup screens:
/// the new screen fades in while sliding from the right, the screen under it
/// drifts left, and going back plays the same motion in reverse.
Route<T> authFadeRoute<T>({
  required String name,
  required WidgetBuilder builder,
  Object? arguments,
}) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: name, arguments: arguments),
    transitionDuration: const Duration(milliseconds: 460),
    reverseTransitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (context, _, __) => builder(context),
    transitionsBuilder: _authSharedAxisTransition,
  );
}

Widget _authSharedAxisTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;

  final enter = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  final enterFade = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    reverseCurve: const Interval(0.3, 1.0, curve: Curves.easeIn),
  );
  final exit = CurvedAnimation(
    parent: secondaryAnimation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  return SlideTransition(
    position: Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.12, 0),
    ).animate(exit),
    child: FadeTransition(
      opacity: enterFade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.14, 0),
          end: Offset.zero,
        ).animate(enter),
        child: child,
      ),
    ),
  );
}

/// How many signup screens sit above the login screen that opened them
/// (0 when signup was not opened from login).
int _loginDepth(BuildContext context) {
  final args = ModalRoute.of(context)?.settings.arguments;
  if (args is! Map || args[_kFromLoginArg] != true) return 0;
  final depth = args[_kLoginDepthArg];
  return depth is int && depth > 0 ? depth : 1;
}

/// Login → account type chooser.
void openSignupFromLogin(BuildContext context) {
  Navigator.pushNamed(
    context,
    '/signup',
    arguments: const {_kFromLoginArg: true, _kLoginDepthArg: 1},
  );
}

/// Account type chooser → a signup form, remembering how far back login is.
void openSignupStep(BuildContext context, String route) {
  final depth = _loginDepth(context);
  Navigator.pushNamed(
    context,
    route,
    arguments: depth == 0
        ? null
        : {_kFromLoginArg: true, _kLoginDepthArg: depth + 1},
  );
}

/// Signup → login. Pops back to the login screen (reversing the transition)
/// when signup was opened from it; otherwise replaces this screen with login.
void openLoginFromSignup(BuildContext context) {
  final depth = _loginDepth(context);
  if (depth > 0) {
    var popped = 0;
    Navigator.popUntil(context, (_) => popped++ >= depth);
    return;
  }
  Navigator.pushReplacementNamed(context, '/login');
}
