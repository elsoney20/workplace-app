import 'package:material_ui/material_ui.dart';

/// Opening a page (a post, a group, a chat...): the new page fades in and
/// rises a few pixels in 180 ms. The page underneath is left alone, so each
/// frame only blends one layer (cheap even on a 4K screen; the default
/// transition animates both pages for 800 ms).
class QuickPageTransitionsBuilder extends PageTransitionsBuilder {
  const QuickPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .012),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
