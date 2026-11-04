import 'dart:ui' show ViewFocusEvent, ViewFocusState;
import 'package:flutter/material.dart';
import '../core/sound.dart';
import '../core/speech.dart';
import 'cat_actor.dart';

class CatDialogue extends StatefulWidget {
  final String text;
  final CatMood mood;
  final SoftSounds? sounds;
  final double size;
  final int? maxLines;
  final bool instant, showSkip, reserveSpace;
  final TextStyle? style;
  const CatDialogue(
    this.text, {
    super.key,
    this.mood = CatMood.explaining,
    this.sounds,
    this.size = 66,
    this.maxLines,
    this.instant = false,
    this.showSkip = true,
    this.reserveSpace = true,
    this.style,
  });
  @override
  State<CatDialogue> createState() => _CatDialogueState();
}

class _CatDialogueState extends State<CatDialogue> with WidgetsBindingObserver {
  late final SpeechTimeline timeline;
  SoftSounds? sounds;
  int? token;
  String? currentText;
  bool active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timeline = SpeechTimeline(
      onSyllable: () {
        if (token != null) {
          sounds?.syllable(
            token!,
            widget.mood,
            question: widget.text.trimRight().endsWith('?'),
          );
        }
      },
      onStop: _stop,
    );
  }

  void _stop() {
    if (token != null) sounds?.finishSpeech(token!);
    token = null;
  }

  void _start() {
    timeline.start(
      widget.text,
      instant:
          widget.instant || !active || MediaQuery.disableAnimationsOf(context),
    );
    if (!timeline.complete &&
        (sounds?.enabled ?? false) &&
        (sounds?.voiceEnabled ?? false)) {
      token = sounds?.claimSpeech();
    }
    currentText = widget.text;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sounds = widget.sounds ?? SoundScope.of(context);
    active =
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
    if (currentText != widget.text) {
      _start();
    } else if (!active || MediaQuery.disableAnimationsOf(context)) {
      timeline.reveal();
    }
  }

  @override
  void didUpdateWidget(CatDialogue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _stop();
      sounds = widget.sounds ?? sounds;
      _start();
    } else if (widget.instant && !oldWidget.instant) {
      timeline.reveal();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) timeline.reveal();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.unfocused) timeline.reveal();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: timeline,
    builder: (context, _) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CatActor(
          size: widget.size,
          mood: widget.mood,
          talking: timeline.talking && active,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: widget.text,
            excludeSemantics: true,
            child: widget.reserveSpace
                ? Stack(
                    children: [
                      Opacity(
                        opacity: 0,
                        child: Text(
                          widget.text,
                          maxLines: widget.maxLines,
                          overflow: widget.maxLines == null
                              ? null
                              : TextOverflow.ellipsis,
                          style: widget.style,
                        ),
                      ),
                      Text(
                        timeline.text,
                        maxLines: widget.maxLines,
                        overflow: widget.maxLines == null
                            ? null
                            : TextOverflow.ellipsis,
                        style: widget.style,
                      ),
                    ],
                  )
                : AnimatedSize(
                    duration: Duration(
                      milliseconds: MediaQuery.disableAnimationsOf(context)
                          ? 0
                          : 140,
                    ),
                    alignment: Alignment.topLeft,
                    curve: Curves.easeOut,
                    child: Text(
                      timeline.text,
                      maxLines: widget.maxLines,
                      overflow: widget.maxLines == null
                          ? null
                          : TextOverflow.ellipsis,
                      style: widget.style,
                    ),
                  ),
          ),
        ),
        if (widget.showSkip)
          IconButton(
            tooltip: 'Показать реплику целиком',
            onPressed: timeline.complete ? null : timeline.reveal,
            icon: const Icon(Icons.fast_forward_rounded),
          ),
      ],
    ),
  );
}
