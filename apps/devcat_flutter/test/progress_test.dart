import 'dart:io';
import 'package:devcat/core/progress.dart';
import 'package:devcat/core/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Merge preserves successes and conflicting device drafts; idempotent',
    () {
      final a = ProgressData()
        ..attempt('python.loops', 'python', true)
        ..draft('python.loops', 'local', 'a');
      final b = ProgressData()
        ..attempt('python.loops', 'python', false)
        ..draft('python.loops', 'phone', 'b');
      final merged = a.merge(b);
      expect(merged.solved, {'python.loops'});
      expect(merged.attempts.length, 2);
      expect(merged.draftsFor('python.loops').length, 2);
      expect(merged.merge(b).encode(), merged.encode());
      expect(a.merge(b).solved, b.merge(a).solved);
    },
  );
  test('Repeated draft saves keep the highest revision for each device', () {
    final a = ProgressData()..draft('task', 'old', 'a');
    final b = ProgressData.decode(a.encode())..draft('task', 'new', 'a');
    expect(a.merge(b).draftsFor('task').single['text'], 'new');
    expect(b.merge(a).draftsFor('task').single['text'], 'new');
  });
  test('Invalid import is rejected before modifying state', () {
    expect(() => ProgressData.decode('{"schema":999}'), throwsFormatException);
    expect(
      () => ProgressData.decode(
        '{"schema":1,"attempts":{},"drafts":{"x":{"updated":1,"revision":1,"text":42}},"cursors":{}}',
      ),
      throwsFormatException,
    );
  });
  test(
    'Store survives restart and recovers backup after truncated primary',
    () async {
      final dir = await Directory.systemTemp.createTemp('devcat-store-test');
      addTearDown(() => dir.delete(recursive: true));
      final store = AppStore(dir);
      await store.load();
      await store.record('python.loops', 'python', true);
      await store.set('theme', 'dark');
      final second = AppStore(dir);
      await second.load();
      expect(second.progress.solved, {'python.loops'});
      expect(second.setting('theme', ''), 'dark');
      expect(second.device, store.device);
      await File('${dir.path}/devcat.json').writeAsString('{truncated');
      final recovered = AppStore(dir);
      await recovered.load();
      expect(recovered.progress.solved, {'python.loops'});
      expect(recovered.storageWarning, isNotNull);
    },
  );
}
