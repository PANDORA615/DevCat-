import 'package:flutter/material.dart';

class LessonVisual extends StatelessWidget {
  final Map<String, dynamic> data;
  const LessonVisual(this.data, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.secondaryContainer.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          data['title'] ?? 'Как устроен пример',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ...(data['boxes'] as List).indexed.expand(
          (e) => [
            if (e.$1 > 0)
              const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.arrow_downward),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                '${e.$1 + 1}. ${e.$2}',
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
