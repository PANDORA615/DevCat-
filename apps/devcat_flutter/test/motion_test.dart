import 'package:devcat/ui/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('Nested learning routes respect reduced motion: $reduced', (
      tester,
    ) async {
      late DevCatRoute<void> route;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  route = DevCatRoute<void>(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: const Text('Лекция')),
                      body: const Text('Подробное объяснение'),
                    ),
                  );
                  Navigator.of(context).push(route);
                },
                child: const Text('Открыть урок'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть урок'));
      await tester.pump();
      expect(
        route.transitionDuration,
        reduced ? Duration.zero : DevCatMotion.page,
      );
      await tester.pumpAndSettle();
      expect(find.text('Подробное объяснение'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Открыть урок'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dialogs and sheets respect reduced motion: $reduced', (
      tester,
    ) async {
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              page = context;
              return const Scaffold(body: Text('Редактор'));
            },
          ),
        ),
      );
      final style = DevCatMotion.style(page);
      expect(style.duration, reduced ? Duration.zero : DevCatMotion.dialog);
      final dialog = showDevCatDialog<void>(
        context: page,
        builder: (_) => const AlertDialog(title: Text('Сохранено')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Сохранено'), findsOneWidget);
      Navigator.of(page).pop();
      await tester.pumpAndSettle();
      await dialog;
      final sheet = showDevCatSheet<void>(
        context: page,
        builder: (_) => const Text('Файлы проекта'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Файлы проекта'), findsOneWidget);
      Navigator.of(page).pop();
      await tester.pumpAndSettle();
      await sheet;
      expect(tester.takeException(), isNull);
    });
  }
}
