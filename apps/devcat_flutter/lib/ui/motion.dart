import 'package:flutter/material.dart';

abstract final class DevCatMotion {
  static const page = Duration(milliseconds: 280);
  static const exit = Duration(milliseconds: 200);
  static const dialog = Duration(milliseconds: 180);
  static const curve = Curves.easeOutCubic;

  static AnimationStyle style(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(duration: dialog, reverseDuration: dialog);
}

/// A short horizontal transition for every nested desktop learning/IDE route.
/// Returning uses the same animation in reverse, preserving spatial direction.
class DevCatRoute<T> extends MaterialPageRoute<T> {
  DevCatRoute({required super.builder, super.settings, super.fullscreenDialog});

  bool get _reduced =>
      navigator != null && MediaQuery.disableAnimationsOf(navigator!.context);
  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : DevCatMotion.page;
  @override
  Duration get reverseTransitionDuration =>
      _reduced ? Duration.zero : DevCatMotion.exit;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final entering = animation.drive(CurveTween(curve: DevCatMotion.curve));
    final leaving = secondaryAnimation.drive(
      CurveTween(curve: DevCatMotion.curve),
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-.035, 0),
      ).animate(leaving),
      child: FadeTransition(
        opacity: entering,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.07, 0),
            end: Offset.zero,
          ).animate(entering),
          child: child,
        ),
      ),
    );
  }
}

Future<T?> showDevCatDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  animationStyle: DevCatMotion.style(context),
);

Future<T?> showDevCatSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool? showDragHandle,
}) => showModalBottomSheet<T>(
  context: context,
  builder: builder,
  isScrollControlled: isScrollControlled,
  showDragHandle: showDragHandle,
  sheetAnimationStyle: DevCatMotion.style(context),
);
