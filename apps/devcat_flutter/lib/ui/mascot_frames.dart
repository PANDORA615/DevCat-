import 'dart:ui' show ViewFocusEvent, ViewFocusState;
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/mascot.dart';
import '../core/mascot_playback.dart';
import '../core/mascot_activity.dart';
import '../core/learning_assets.dart';
import 'package:flutter/scheduler.dart';

class MascotFrames extends StatefulWidget {
  final String appearance, state;
  final double size;
  final bool playing, reactive;
  final bool? mouthOpen;
  final int mouthShape;
  final int? frame;
  final ValueChanged<int>? onFrame;
  const MascotFrames({
    super.key,
    required this.appearance,
    this.state = 'idle',
    required this.size,
    this.playing = true,
    this.reactive = false,
    this.mouthOpen,
    this.mouthShape = 1,
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
  void Function()? stopListening;
  Timer? ambientTimer;
  final ambientClock = Stopwatch();
  int ambientDelay = 0;
  @override
  void initState() {
    super.initState();
    stopListening = MascotActivity.listen(() {
      if (widget.reactive && (playback?.wake() ?? false) && mounted) {
        _stopAmbient(retainElapsed: false);
        _configure();
        setState(() {});
      }
    });
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
    if ({'idle', 'sleeping', 'waiting'}.contains(playback?.state)) {
      _configure();
    }
    if (playback?.completed ?? false) ticker.stop();
    if (mounted &&
        (oldState != playback?.state || oldFrame != playback?.frame)) {
      setState(() {});
    }
  }

  void _configure({bool rebuild = false, bool command = false}) {
    if (catalog == null) return;
    if (rebuild || command) _stopAmbient(retainElapsed: false);
    if (rebuild || playback == null) {
      playback?.dispose();
      final clips = <String, MascotClip>{};
      for (final entry in catalog!.states.entries) {
        final clip = catalog!.clip(widget.appearance, entry.key);
        if (clip != null) {
          clips[entry.key] = MascotClip.fromJson(clip);
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
      playback!.play(widget.state, force: !widget.reactive);
    }
    if (widget.frame != null && widget.frame != playback!.frame) {
      playback!.seek(widget.frame!);
    }
    final animate =
        widget.playing &&
        (widget.reactive ||
            catalog!.clip(widget.appearance, widget.state) != null) &&
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
      if ({'idle', 'sleeping', 'waiting'}.contains(playback!.state)) {
        ticker.stop();
        lastTick = null;
        if (ambientTimer == null) {
          ambientDelay = playback!.millisecondsToNextFrame;
          ambientClock.reset();
          ambientClock.start();
          ambientTimer = Timer(Duration(milliseconds: ambientDelay), () {
            ambientTimer = null;
            ambientClock.stop();
            if (!mounted) return;
            final oldState = playback!.state, oldFrame = playback!.frame;
            playback!.advance(ambientDelay);
            _configure();
            if (oldState != playback!.state || oldFrame != playback!.frame) {
              setState(() {});
            }
          });
        }
        return;
      }
      _stopAmbient();
      if (!ticker.isActive) {
        lastTick = null;
        ticker.start();
      }
    } else {
      _stopAmbient();
      playback!.pause();
      ticker.stop();
      lastTick = null;
    }
  }

  void _stopAmbient({bool retainElapsed = true}) {
    if (ambientTimer == null) return;
    ambientTimer!.cancel();
    ambientTimer = null;
    ambientClock.stop();
    if (retainElapsed) {
      playback?.advance(
        ambientClock.elapsedMilliseconds.clamp(0, ambientDelay - 1),
      );
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
    _stopAmbient(retainElapsed: false);
    stopListening?.call();
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
        final image = Image.asset(
          MascotCatalog.asset(path),
          bundle: LearningAssets.bundle,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          semanticLabel:
              '${data.appearance(widget.appearance)['title']} · ${clip?['title'] ?? 'Статичный образ'}',
          errorBuilder: (_, _, _) => Image.asset(
            MascotCatalog.asset(data.appearance(widget.appearance)['asset']),
            bundle: LearningAssets.bundle,
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
        if (widget.mouthOpen == null || clip?['kind'] == 'views') return image;
        final frame = playback?.frame ?? 0;
        final anchors = clip?['mouthAnchors'] as List?;
        final anchor = anchors == null
            ? const [60, 72]
            : anchors[frame] as List;
        return CustomPaint(
          foregroundPainter: _SpeechMouth(
            Offset(
              (anchor[0] as num).toDouble(),
              (anchor[1] as num).toDouble(),
            ),
            widget.mouthOpen!,
            widget.mouthShape,
          ),
          child: image,
        );
      },
    );
  }
}

class _SpeechMouth extends CustomPainter {
  final Offset anchor;
  final bool open;
  final int shape;
  _SpeechMouth(this.anchor, this.open, this.shape);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 128, size.height / 128);
    final pixel = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xff151220);
    // Covers the authored mouth only, keeping eyes/scarf/accessories intact.
    canvas.drawRect(Rect.fromLTWH(anchor.dx - 4, anchor.dy - 4, 16, 12), pixel);
    pixel.color = open ? const Color(0xfff59ac4) : const Color(0xff58398d);
    final mouth = !open
        ? const Rect.fromLTWH(0, 0, 8, 4)
        : switch (shape % 3) {
            0 => const Rect.fromLTWH(-4, 0, 16, 4),
            1 => const Rect.fromLTWH(0, -4, 8, 8),
            _ => const Rect.fromLTWH(0, -4, 4, 8),
          };
    canvas.drawRect(mouth.shift(anchor), pixel);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpeechMouth old) =>
      anchor != old.anchor || open != old.open || shape != old.shape;
}
