import 'dart:ui' show ViewFocusEvent, ViewFocusState;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/mascot.dart';
import '../core/mascot_playback.dart';
import '../core/mascot_stage.dart';
import 'mascot_frames.dart';

class MascotPlayground extends StatefulWidget {
  final MascotCatalog catalog;
  final String appearance;
  const MascotPlayground({
    super.key,
    required this.catalog,
    this.appearance = 'student',
  });
  @override
  State<MascotPlayground> createState() => _MascotPlaygroundState();
}

class _MascotPlaygroundState extends State<MascotPlayground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  MascotStage _createStage() => MascotStage({
    for (final entry
        in (widget.catalog.clips[widget.appearance] as Map<String, dynamic>)
            .entries)
      if (entry.value['kind'] != 'views')
        entry.key: MascotClip.fromJson(entry.value),
  });
  late MascotStage stage = _createStage();
  bool get hasMotion => stage.playback.clips.keys.toSet().containsAll({
    'walk',
    'run',
    'jump',
    'land',
  });
  @override
  void didUpdateWidget(MascotPlayground old) {
    super.didUpdateWidget(old);
    if (old.appearance != widget.appearance) {
      ticker.stop();
      stage.dispose();
      stage = _createStage();
      previous = null;
      _configure();
    }
  }

  late final Ticker ticker = createTicker(_tick);
  Duration? previous;
  bool foreground = true, focused = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _tick(Duration elapsed) {
    final before = previous;
    previous = elapsed;
    if (before == null) return;
    stage.advance((elapsed - before).inMilliseconds);
    if (stage.playback.state == 'idle') ticker.stop();
    setState(() {});
  }

  void _configure() {
    final enabled =
        foreground &&
        focused &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled && stage.playback.state != 'idle') {
      stage.playback.resume();
      if (!ticker.isActive) {
        previous = null;
        ticker.start();
      }
    } else {
      ticker.stop();
      stage.playback.pause();
      previous = null;
    }
  }

  void _act(void Function() action) {
    action();
    _configure();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
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
    ticker.dispose();
    stage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Поиграть с котом', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          reduced
              ? 'Движение отключено настройкой «Меньше анимаций».'
              : !hasMotion
              ? 'Для движения выбери образ «Ученик». Здесь сохраняется твой выбранный костюм.'
              : 'Кот двигается только в этом окошке и останавливается у края. После прыжка сначала приземляется.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            stage.resize(constraints.maxWidth);
            return ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: SizedBox(
                  height: 148,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Divider(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      Positioned(
                        left: stage.x,
                        bottom: 12,
                        child: MascotFrames(
                          appearance: widget.appearance,
                          state: stage.playback.state,
                          size: stage.spriteSize,
                          playing: false,
                          frame: stage.playback.frame,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: reduced || !hasMotion
                  ? null
                  : () => _act(() => stage.move(-1)),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Влево'),
            ),
            OutlinedButton.icon(
              onPressed: reduced || !hasMotion
                  ? null
                  : () => _act(() => stage.move(1)),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Вправо'),
            ),
            OutlinedButton(
              onPressed: reduced || !hasMotion
                  ? null
                  : () =>
                        _act(() => stage.move(stage.direction, running: true)),
              child: const Text('Бежать'),
            ),
            OutlinedButton(
              onPressed: reduced || !hasMotion ? null : () => _act(stage.jump),
              child: const Text('Прыгнуть'),
            ),
            OutlinedButton(
              onPressed: reduced || !hasMotion ? null : () => _act(stage.stop),
              child: const Text('Остановиться'),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Скорость'),
            Expanded(
              child: Slider(
                min: 20,
                max: 100,
                divisions: 16,
                value: stage.speed,
                label: '${(stage.speed / 36 * 100).round()}%',
                onChanged: reduced || !hasMotion
                    ? null
                    : (value) => setState(() => stage.speed = value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
