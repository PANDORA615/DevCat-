import 'dart:ui' show ViewFocusEvent, ViewFocusState;
import 'package:flutter/material.dart';
import '../core/mascot.dart';
import '../core/mascot_playback.dart';
import 'package:flutter/scheduler.dart';

class MascotFrames extends StatefulWidget {
  final String appearance, state;
  final double size;
  final bool playing, reactive;
  final int? frame;
  final ValueChanged<int>? onFrame;
  const MascotFrames({
    super.key,
    required this.appearance,
    this.state = 'idle',
    required this.size,
    this.playing = true,
    this.reactive = false,
    this.frame,
    this.onFrame,
  });
  @override
  State<MascotFrames> createState() => _MascotFramesState();
}

class _MascotFramesState extends State<MascotFrames>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static int _nextSeed = 0;
  final int _seed = ++_nextSeed;
  late final Ticker ticker = createTicker(_tick);
  MascotCatalog? catalog;
  MascotPlayback? playback;
  bool unavailable = false, foreground = true, focused = true;
  Duration? lastTick;
  int carryMicros = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    catalog = MascotCatalog.cached;
    MascotCatalog.load().then(
      (value) {
        if (!mounted) return;
        catalog = value;
        _configure(rebuild: true);
        setState(() {});
      },
      onError: (Object _) {
        if (mounted) setState(() => unavailable = true);
      },
    );
  }

  void _tick(Duration elapsed) {
    final previous = lastTick;
    lastTick = elapsed;
    if (previous == null) return;
    final micros = (elapsed - previous).inMicroseconds + carryMicros;
    carryMicros = micros % 1000;
    final oldState = playback?.state, oldFrame = playback?.frame;
    playback?.advance(micros ~/ 1000);
    if (playback?.completed ?? false) ticker.stop();
    if (mounted &&
        (oldState != playback?.state || oldFrame != playback?.frame)) {
      setState(() {});
    }
  }

  void _configure({bool rebuild = false, bool command = false}) {
    if (catalog == null) return;
    if (rebuild || playback == null) {
      playback?.dispose();
      final clips = <String, MascotClip>{};
      for (final entry in catalog!.states.entries) {
        if (catalog!.clip(widget.appearance, entry.key) != null) {
          clips[entry.key] = MascotClip.fromJson(
            Map<String, dynamic>.from(entry.value),
          );
        }
      }
      playback = MascotPlayback(
        clips,
        ambient: widget.reactive,
        followTransitions: widget.reactive,
        seed: _seed,
      );
      playback!.play(widget.state, force: true);
    } else if (command) {
      playback!.play(widget.state);
    }
    if (widget.frame != null && widget.frame != playback!.frame) {
      playback!.seek(widget.frame!);
    }
    final animate =
        widget.playing &&
        widget.frame == null &&
        playback!.clips.isNotEmpty &&
        !playback!.completed &&
        foreground &&
        focused &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      playback!.resume();
      if (!ticker.isActive) {
        lastTick = null;
        ticker.start();
      }
    } else {
      playback!.pause();
      ticker.stop();
      lastTick = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(MascotFrames old) {
    super.didUpdateWidget(old);
    if (!old.playing && widget.playing && (playback?.completed ?? false)) {
      playback!.seek(0);
    }
    _configure(
      rebuild:
          old.appearance != widget.appearance ||
          old.reactive != widget.reactive,
      command: old.state != widget.state,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    _configure();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    focused = event.state == ViewFocusState.focused;
    _configure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    playback?.dispose();
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = catalog;
    if (data == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: unavailable
            ? const Icon(Icons.image_not_supported_outlined)
            : null,
      );
    }
    final clip = data.clip(widget.appearance, playback?.state ?? widget.state);
    return Builder(
      builder: (context) {
        String path;
        if (clip == null) {
          path = data.appearance(widget.appearance)['asset'];
        } else {
          final index = playback?.frame ?? 0;
          widget.onFrame?.call(index);
          path = (clip['frames'] as List)[index];
        }
        return Image.asset(
          MascotCatalog.asset(path),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          semanticLabel:
              '${data.appearance(widget.appearance)['title']} · ${clip?['title'] ?? 'Статичный образ'}',
          errorBuilder: (_, _, _) => Image.asset(
            MascotCatalog.asset(data.appearance(widget.appearance)['asset']),
            width: widget.size,
            height: widget.size,
            filterQuality: FilterQuality.none,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => SizedBox(
              width: widget.size,
              height: widget.size,
              child: const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        );
      },
    );
  }
}
