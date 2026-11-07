import 'package:flutter/material.dart';

/// Animates a persistent page stack; rapid taps retarget one transition.
class NavigationMotion extends StatefulWidget {
  final int selected;
  final bool reduced;
  final Widget child;
  const NavigationMotion({
    super.key,
    required this.selected,
    required this.reduced,
    required this.child,
  });
  @override
  State<NavigationMotion> createState() => _NavigationMotionState();
}

class _NavigationMotionState extends State<NavigationMotion>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  double direction = 1;
  @override
  void didUpdateWidget(NavigationMotion old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      direction = widget.selected > old.selected ? 1 : -1;
      if (widget.reduced) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    }
    if (widget.reduced) controller.value = 1;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (_, child) {
      final value = Curves.easeOutCubic.transform(controller.value);
      return FractionalTranslation(
        translation: Offset((1 - value) * .06 * direction, 0),
        child: Opacity(opacity: .6 + .4 * value, child: child),
      );
    },
  );
}
