import 'package:flutter/material.dart';

/// Ring, circular body and glyph share one explicit center at every density.
class LessonPathCircle extends StatelessWidget {
  final int levels;
  final bool active, unlocked;
  final VoidCallback onTap;
  const LessonPathCircle({
    super.key,
    required this.levels,
    required this.active,
    required this.unlocked,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 92,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          if (active || levels > 0)
            Center(
              child: SizedBox.square(
                dimension: 90,
                child: CircularProgressIndicator(
                  key: const ValueKey('lesson-ring'),
                  value: levels / 3,
                  strokeWidth: 5,
                  color: scheme.primary,
                  backgroundColor: scheme.outlineVariant,
                ),
              ),
            ),
          Center(
            child: SizedBox.square(
              dimension: 73,
              child: Material(
                key: const ValueKey('lesson-body'),
                color: unlocked
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: Center(
                    child: Icon(
                      !unlocked
                          ? Icons.lock_rounded
                          : levels == 3
                          ? Icons.check_rounded
                          : Icons.star_rounded,
                      key: const ValueKey('lesson-icon'),
                      size: 37,
                      color: unlocked
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
