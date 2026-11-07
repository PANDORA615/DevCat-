import 'dart:async';
import 'dart:io';
import 'package:devcat/core/sound.dart';
import 'package:devcat/core/store.dart';
import 'package:devcat/core/updates.dart';
import 'package:devcat/ui/update_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PanelStore extends AppStore {
  PanelStore() : super(Directory('/tmp/devcat-panel-memory')) {
    device = 'panel';
  }
  Completer<void>? saving;
  @override
  Future<void> save() => saving?.future ?? Future<void>.value();
}

class PanelUpdateService extends UpdateService {
  final attempts = <UpdateCancellation>[];
  Completer<void>? finishing;
  PanelUpdateService() : super(publicKey: 'test-only');
  @override
  Future<VerifiedUpdate> check({
    required String owner,
    required String repo,
    required String channel,
    UpdateCancellation? cancellation,
  }) async => VerifiedUpdate({
    'schemaVersion': 1,
    'version': '0.9.3',
    'channel': channel,
    'minSupportedAppVersion': '0.9.2',
    'releaseNotes': 'Новые уроки',
    'content': {
      'url': 'https://example.com/courses.json',
      'size': 1024,
      'sha256': '0' * 64,
    },
  }, channel);
  @override
  Future<void> installContent(
    VerifiedUpdate update,
    AppStore store, {
    UpdateCancellation? cancellation,
    UpdateProgressCallback? onProgress,
  }) async {
    attempts.add(cancellation!);
    finishing = Completer<void>();
    onProgress?.call(const UpdateDownloadProgress(512, 1024, 256));
    await cancellation.race(finishing!.future);
  }
}

void main() {
  testWidgets('Update panel displays progress, cancels and can retry', (
    tester,
  ) async {
    final store = PanelStore();
    final sounds = SoftSounds()..enabled = false;
    addTearDown(sounds.dispose);
    final service = PanelUpdateService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UpdatePanel(
              store: store,
              sounds: sounds,
              serviceFactory: () => service,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Проверить обновления'));
    await tester.pumpAndSettle();
    expect(find.text('Доступна версия 0.9.3'), findsOneWidget);
    await tester.tap(find.text('Скачать и проверить курсы'));
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .5,
    );
    expect(find.textContaining('50%'), findsOneWidget);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((field) => field.enabled == false),
      true,
    );
    await tester.tap(find.text('Отменить загрузку'));
    await tester.pumpAndSettle();
    expect(service.attempts.single.isCancelled, true);
    expect(
      find.text('Загрузка отменена. Текущие курсы сохранены.'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Скачать и проверить курсы'));
    await tester.pump();
    expect(service.attempts.length, 2);
    expect(service.attempts.last.isCancelled, false);
    service.finishing!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Курсы обновлены. Перезапусти приложение для применения.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Скачать и проверить курсы'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(service.attempts.last.isCancelled, true);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Rollback cannot be mistaken for a cancellable download', (
    tester,
  ) async {
    final store = PanelStore();
    store.settings['contentUpdateActive'] = '0.9.3';
    store.saving = Completer<void>();
    final sounds = SoftSounds()..enabled = false;
    addTearDown(sounds.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UpdatePanel(
              store: store,
              sounds: sounds,
              serviceFactory: PanelUpdateService.new,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Откатить курсы'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Отменить загрузку'), findsNothing);
    store.saving!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Восстановлена предыдущая версия. Перезапусти приложение.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
