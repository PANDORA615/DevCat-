import 'package:flutter/material.dart';
import '../core/sound.dart';
import '../core/mascot.dart';
import 'mascot_frames.dart';

/// Gestures and speech use separate layers: punctuation closes only the mouth,
/// without restarting a gesture or replacing the selected costume.
class CatActor extends StatelessWidget {
  final double size;
  final CatMood mood;
  final bool? talking;
  final String? action;
  final int mouthShape;
  const CatActor({
    super.key,
    required this.size,
    this.mood = CatMood.greeting,
    this.talking,
    this.action,
    this.mouthShape = 1,
  });
  @override
  Widget build(BuildContext context) {
    final selected = MascotScope.of(context);
    return MascotFrames(
      appearance: selected == 'classic' ? 'book' : selected,
      reactive: true,
      state:
          action ??
          switch (mood) {
            CatMood.greeting => 'idle',
            CatMood.celebration => 'happy',
            CatMood.explaining => 'explaining',
            CatMood.thinking => 'thinking',
            CatMood.warning => 'error',
            CatMood.encouragement => 'thoughtful',
          },
      size: size,
      mouthOpen: talking,
      mouthShape: mouthShape,
    );
  }
}
