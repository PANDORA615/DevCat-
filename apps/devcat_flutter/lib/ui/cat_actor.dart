import 'dart:async';
import 'package:flutter/material.dart';
import '../core/mascot.dart';
import '../core/sound.dart';

/// Original v5 and exported appearance PNGs; no atlas slicing at runtime.
class CatActor extends StatefulWidget {
  final double size;
  final CatMood mood;
  final String? speech, appearanceId, action;
  final CatAnimationController? controller;
  const CatActor({
    super.key,
    required this.size,
    this.mood = CatMood.greeting,
    this.speech,
    this.appearanceId,
    this.action,
    this.controller,
  });
  @override
  State<CatActor> createState() => _CatActorState();
}

class _CatActorState extends State<CatActor> with WidgetsBindingObserver {
  late CatAnimationController controller;
  Timer? timer;
  DateTime lastTick = DateTime.now();
  int idleMs = 0, blinkAt = 4000;
  bool foreground = true, reduced = false, visible = true, initialized = false;
  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? CatAnimationController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    visible = TickerMode.valuesOf(context).enabled;
    final identity = widget.appearanceId ?? MascotScope.of(context);
    final changed =
        widget.controller == null && controller.appearanceId != identity;
    if (widget.controller == null) controller.selectAppearance(identity);
    if (!initialized || changed) _react();
    initialized = true;
    if (!visible && widget.speech != null) controller.cancel();
    _schedule();
  }

  @override
  void didUpdateWidget(CatActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) controller.dispose();
      controller =
          widget.controller ??
          CatAnimationController(
            appearanceId: widget.appearanceId ?? MascotScope.of(context),
          );
      _react();
    }
    if (widget.controller == null &&
        oldWidget.appearanceId != widget.appearanceId) {
      controller.selectAppearance(
        widget.appearanceId ?? MascotScope.of(context),
      );
    }
    if (oldWidget.speech != widget.speech ||
        oldWidget.mood != widget.mood ||
        oldWidget.action != widget.action) {
      _react();
    }
    _schedule();
  }

  void _react() {
    if (widget.controller != null) return;
    idleMs = 0;
    blinkAt = 4000;
    controller.play(
      widget.action ??
          (widget.speech != null
              ? 'talk'
              : catStateForMood(
                  widget.mood,
                  appearanceId: controller.appearanceId,
                )),
      force: true,
    );
  }

  void _schedule() {
    timer?.cancel();
    if (!foreground || !visible || reduced || !controller.hasClip) return;
    lastTick = DateTime.now();
    timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final now = DateTime.now();
      final delta = now.difference(lastTick).inMilliseconds;
      lastTick = now;
      controller.advance(delta);
      if (widget.controller != null) return;
      idleMs += delta;
      if (widget.speech != null &&
          controller.state == 'talk' &&
          idleMs >= widget.speech!.characters.length * 35) {
        controller.cancel();
      } else if (controller.state == 'idle' && idleMs >= blinkAt) {
        controller.play('blink');
        blinkAt = idleMs + 3000 + (idleMs % 4001);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      controller.pause();
    } else if (widget.controller != null || widget.speech == null) {
      controller.resume();
    } else {
      controller.cancel();
    }
    _schedule();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Кот DevCat: ${MascotCatalog.appearance(controller.appearanceId).title}',
    image: true,
    child: SizedBox.square(
      dimension: widget.size,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Image.asset(
          reduced ? controller.restAsset : controller.asset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context))
              .ceil(),
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => Image.asset(
            MascotCatalog.appearance(controller.appearanceId).asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context))
                .ceil(),
            errorBuilder: (_, _, _) => Center(
              child: Text(
                MascotCatalog.appearance(controller.appearanceId).title,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
