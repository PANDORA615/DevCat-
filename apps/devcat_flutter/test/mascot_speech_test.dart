import 'package:devcat/core/mascot_speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text is revealed from elapsed time, not repaint count', () {
    final p = MascotTextReveal('Привет!', correlationId: 'line-1');
    p.advance(const Duration(milliseconds: 34));
    expect(p.visibleText, '');
    p.advance(const Duration(milliseconds: 1));
    expect(p.visibleText, 'П');
    expect(p.mouthActive, isTrue);
    p.advance(const Duration(milliseconds: 175));
    expect(p.visibleText, 'Привет');
    expect(p.complete, isFalse);
    p.advance(const Duration(milliseconds: 110));
    expect(p.visibleText, 'Привет!');
    expect(p.complete, isTrue);
    expect(p.mouthActive, isFalse);
  });

  test('spaces and punctuation pause the mouth', () {
    final p = MascotTextReveal('А Б.', correlationId: 'two');
    p.advance(const Duration(milliseconds: 35));
    expect(p.mouthActive, isTrue);
    p.advance(const Duration(milliseconds: 110));
    expect(p.visibleText, 'А ');
    expect(p.mouthActive, isFalse);
    p.advance(const Duration(milliseconds: 35));
    expect(p.visibleText, 'А Б');
    expect(p.mouthActive, isTrue);
    p.advance(const Duration(milliseconds: 110));
    expect(p.mouthActive, isFalse);
  });

  test('skip shows the full line and cancels mouth animation', () {
    final p = MascotTextReveal('Длинная реплика', correlationId: 'skip');
    p.advance(const Duration(milliseconds: 35));
    p.skip();
    p.advance(const Duration(seconds: 5));
    expect(p.visibleText, 'Длинная реплика');
    expect(p.complete, isTrue);
    expect(p.mouthActive, isFalse);
  });

  test('cancel prevents stale reveal from progressing', () {
    final old = MascotTextReveal('Старый текст', correlationId: 'old');
    final current = MascotTextReveal('Новый текст', correlationId: 'new');
    old.cancel();
    old.advance(const Duration(seconds: 3));
    current.advance(const Duration(milliseconds: 35));
    expect(old.visibleText, '');
    expect(old.cancelled, isTrue);
    expect(current.visibleText, 'Н');
    expect(current.cancelled, isFalse);
  });

  test('surrogate pairs are never split mid-character', () {
    final p = MascotTextReveal('🐈У', correlationId: 'unicode');
    p.advance(const Duration(milliseconds: 35));
    expect(p.visibleText, '🐈');
    p.advance(const Duration(milliseconds: 35));
    expect(p.visibleText, '🐈У');
  });

  test('negative elapsed durations are rejected', () {
    final p = MascotTextReveal('a', correlationId: 'invalid');
    expect(
      () => p.advance(const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
  });
}
