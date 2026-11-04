import 'package:flutter/material.dart';
import '../core/mascot.dart';

class MascotFrames extends StatefulWidget {
  final String appearance, state;
  final double size;
  final bool playing;
  final int? frame;
  final ValueChanged<int>? onFrame;
  const MascotFrames({
    super.key,
    required this.appearance,
    this.state = 'idle',
    required this.size,
    this.playing = true,
    this.frame,
    this.onFrame,
  });
  @override
  State<MascotFrames> createState() => _MascotFramesState();
}

class _MascotFramesState extends State<MascotFrames>
    with SingleTickerProviderStateMixin {
  late final AnimationController clock = AnimationController(vsync: this);
  MascotCatalog? catalog;
  bool unavailable = false;
  @override
  void initState() {
    super.initState();
    catalog = MascotCatalog.cached;
    MascotCatalog.load().then(
      (value) {
        if (!mounted) return;
        setState(() => catalog = value);
        _start();
      },
      onError: (Object _) {
        if (mounted) setState(() => unavailable = true);
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start();
  }

  @override
  void didUpdateWidget(MascotFrames oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.appearance != widget.appearance ||
        oldWidget.playing != widget.playing ||
        oldWidget.frame != widget.frame) {
      _start(
        restart:
            oldWidget.state != widget.state ||
            oldWidget.appearance != widget.appearance,
      );
    }
  }

  void _start({bool restart = true}) {
    clock.stop();
    if (restart) clock.value = 0;
    final clip = catalog?.clip(widget.appearance, widget.state);
    if (clip == null) {
      return;
    }
    clock.duration = Duration(
      milliseconds: (clip['durationsMs'] as List).cast<int>().fold<int>(
        0,
        (a, b) => a + b,
      ),
    );
    if (widget.frame != null) {
      final durations = List<int>.from(clip['durationsMs']);
      clock.value =
          durations
              .take(widget.frame!.clamp(0, durations.length - 1))
              .fold<int>(0, (a, b) => a + b) /
          clock.duration!.inMilliseconds;
      return;
    }
    if (!widget.playing || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    if (clip['loop'] == true) {
      clock.repeat();
    } else {
      clock.forward();
    }
  }

  @override
  void dispose() {
    clock.dispose();
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
    final clip = data.clip(widget.appearance, widget.state);
    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        String path;
        if (clip == null) {
          path = data.appearance(widget.appearance)['asset'];
        } else {
          final durations = List<int>.from(clip['durationsMs']);
          final elapsed =
              (clock.value * durations.fold<int>(0, (a, b) => a + b)).round();
          final index =
              widget.frame?.clamp(0, durations.length - 1) ??
              mascotFrame(durations, elapsed, loop: clip['loop'] == true);
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
