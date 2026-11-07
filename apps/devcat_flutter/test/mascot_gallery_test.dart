import 'dart:io';
import 'package:devcat/core/mascot.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/core/store.dart';
import 'package:devcat/ui/mascot_frames.dart';
import 'package:devcat/ui/mascot_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class GalleryStore extends AppStore {
  GalleryStore() : super(Directory('/tmp/devcat-gallery-test')) {
    device = 'gallery-test';
  }
  @override
  Future<void> save() async {}
}

void main() {
  testWidgets(
    'Gallery steps real frames, preserves a missing costume clip and saves selection',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => MascotCatalog.load());
      final store = GalleryStore();
      final sounds = SoftSounds()..enabled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MascotGallery(store: store, sounds: sounds),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ученик'), findsWidgets);
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      final selectAppearance = tester
          .widget<DropdownButtonFormField<String>>(dropdowns.first)
          .onChanged!;
      final selectState = tester
          .widget<DropdownButtonFormField<String>>(dropdowns.at(1))
          .onChanged!;
      selectState('talk');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Следующий кадр'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Следующий кадр'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MascotFrames>(find.byType(MascotFrames).last).frame,
        1,
      );
      selectState('reading');
      selectAppearance('pirate');
      await tester.pumpAndSettle();
      expect(find.textContaining('Клип не подготовлен.'), findsOneWidget);
      final actor = tester.widget<MascotFrames>(find.byType(MascotFrames).last);
      expect(actor.appearance, 'pirate');
      await tester.scrollUntilVisible(
        find.text('Носить этот образ'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Носить этот образ'));
      await tester.pumpAndSettle();
      expect(store.setting('mascotAppearance', 'classic'), 'pirate');
      expect(store.progress.attempts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await sounds.dispose();
    },
  );
}
