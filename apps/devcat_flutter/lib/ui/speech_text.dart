import 'dart:async';
import 'package:flutter/material.dart';
import '../core/sound.dart';

/// Grapheme-aware reveal; skipping, route changes and background cancel voice.
class SpeechText extends StatefulWidget {
  final String text;
  final CatMood mood;
  final SoftSounds? sounds;
  final bool instant;
  final int? maxLines;
  final TextStyle? style;
  const SpeechText({
    super.key,
    required this.text,
    required this.mood,
    this.sounds,
    this.instant = false,
    this.maxLines,
    this.style,
  });
  @override
  State<SpeechText> createState() => _SpeechTextState();
}

class _SpeechTextState extends State<SpeechText> with WidgetsBindingObserver {
  Timer? timer;
  List<String> characters = [];
  int count = 0, elapsedMs = 0;
  SpeechBudget budget = SpeechBudget();
  SoftSounds? sounds;
  bool reduced = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sounds = widget.sounds ?? SoundScope.of(context);
    final nextReduced = MediaQuery.disableAnimationsOf(context);
    final visible = TickerMode.valuesOf(context).enabled;
    if (!visible) {
      _finish();
      return;
    }
    if (characters.isEmpty || reduced != nextReduced) {
      reduced = nextReduced;
      _start();
    }
  }

  @override
  void didUpdateWidget(SpeechText oldWidget) {
    super.didUpdateWidget(oldWidget);
    sounds = widget.sounds ?? sounds;
    if (oldWidget.text != widget.text || oldWidget.instant != widget.instant) {
      _start();
    }
  }

  void _start() {
    timer?.cancel();
    sounds?.stopVoice();
    characters = widget.text.characters.toList();
    count = widget.instant || reduced ? characters.length : 0;
    elapsedMs = 0;
    budget = SpeechBudget();
    if (count == characters.length) {
      if (reduced && !widget.instant && characters.length >= 3) {
        sounds?.speak(widget.mood);
      }
      return;
    }
    timer = Timer.periodic(const Duration(milliseconds: 35), (_) {
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
        _finish();
        return;
      }
      setState(() {
        count++;
        elapsedMs += 35;
      });
      final visible = characters.take(count).join();
      if (budget.request(visible, elapsedMs)) sounds?.speak(widget.mood);
      if (count >= characters.length) _finish();
    });
  }

  void _finish() {
    timer?.cancel();
    sounds?.stopVoice();
    if (mounted) setState(() => count = characters.length);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _finish();
  }

  @override
  void dispose() {
    timer?.cancel();
    sounds?.stopVoice();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    characters.take(count).join(),
    style: widget.style,
    maxLines: widget.maxLines,
    overflow: widget.maxLines == null
        ? TextOverflow.clip
        : TextOverflow.ellipsis,
  );
}
