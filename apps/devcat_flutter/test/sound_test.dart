import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/core/learning_assets.dart';
import 'package:flutter_test/flutter_test.dart';

class NativeAudioDouble implements AudioPlayer {
  final completion = StreamController<void>.broadcast(sync: true);
  final started = <String>[];
  int stops = 0;
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #onPlayerComplete) return completion.stream;
    if (call.memberName == #play) {
      final source = call.positionalArguments.first as Source;
      started.add(
        source is AssetSource ? source.path : (source as DeviceFileSource).path,
      );
      return Future<void>.value();
    }
    if (call.memberName == #stop) {
      stops++;
      return Future<void>.value();
    }
    if (call.memberName == #dispose) return completion.close();
    return super.noSuchMethod(call);
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
void main() {
  test(
    'Verified snapshot sounds use their local files without another download',
    () async {
      LearningAssets.mediaPaths = {
        'assets/audio/cat_voice_happy.wav':
            '/snapshot/assets/audio/cat_voice_happy.wav',
      };
      addTearDown(() => LearningAssets.mediaPaths = const {});
      final native = NativeAudioDouble();
      final sounds = SoftSounds(createPlayer: () => native);
      sounds.syllable(sounds.claimSpeech(), CatMood.celebration);
      await flush();
      expect(native.started, ['/snapshot/assets/audio/cat_voice_happy.wav']);
      await sounds.dispose();
    },
  );
  test(
    'Voice waits for real completion, drops pulses, and old cancellation cannot stop a new owner',
    () async {
      final native = NativeAudioDouble();
      final sounds = SoftSounds(createPlayer: () => native);
      final old = sounds.claimSpeech();
      for (var i = 0; i < 20; i++) {
        sounds.syllable(old, CatMood.explaining);
      }
      await flush();
      expect(native.started.length, 1);
      expect(sounds.voiceBusy, true);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      sounds.syllable(old, CatMood.explaining);
      await flush();
      expect(
        native.started.length,
        1,
        reason: 'Elapsed sample metadata does not override native completion',
      );
      native.completion.add(null);
      sounds.syllable(old, CatMood.explaining);
      await flush();
      expect(native.started.length, 2);
      final newer = sounds.claimSpeech();
      sounds.syllable(newer, CatMood.celebration);
      await flush();
      final before = native.stops;
      sounds.finishSpeech(old);
      await flush();
      expect(native.stops, before);
      expect(sounds.voiceBusy, true);
      sounds.finishSpeech(newer);
      await flush();
      expect(sounds.voiceBusy, false);
      expect(native.stops, greaterThan(before));
      await sounds.dispose();
    },
  );
}
