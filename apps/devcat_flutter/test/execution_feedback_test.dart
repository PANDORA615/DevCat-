import 'package:devcat/core/execution_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Fast completion cannot be overwritten by a delayed loading event',
    (tester) async {
      final feedback = ExecutionFeedback(() {});
      final ticket = feedback.begin();
      feedback.finish(ticket, ok: true);
      await tester.pump(const Duration(seconds: 2));
      expect(feedback.reaction, ExecutionReaction.success);
      expect(feedback.message, contains('Сравни вывод'));
      feedback.dispose();
    },
  );
  testWidgets('Only the current execution owns its result', (tester) async {
    final feedback = ExecutionFeedback(() {});
    final old = feedback.begin();
    final current = feedback.begin();
    feedback.finish(old, ok: false);
    expect(feedback.reaction, ExecutionReaction.idle);
    await tester.pump(const Duration(milliseconds: 701));
    expect(feedback.animation, 'loading');
    feedback.finish(current, ok: false, cancelled: true);
    expect(feedback.reaction, ExecutionReaction.cancelled);
    expect(feedback.animation, 'waiting');
    feedback.dispose();
  });
  testWidgets('Leaving a project or disposing drops all late events', (
    tester,
  ) async {
    var changes = 0;
    final feedback = ExecutionFeedback(() => changes++);
    final old = feedback.begin();
    feedback.clear();
    final before = changes;
    feedback.finish(old, ok: true);
    await tester.pump(const Duration(seconds: 2));
    expect(changes, before);
    expect(feedback.reaction, ExecutionReaction.idle);
    final current = feedback.begin();
    feedback.dispose();
    final disposed = changes;
    feedback.finish(current, ok: false);
    await tester.pump(const Duration(seconds: 2));
    expect(changes, disposed);
  });
}
