import 'dart:async';
import 'package:flutter/material.dart';
import '../core/cat_chatter.dart';
import '../core/sound.dart';
import 'widgets.dart';

class CompanionBar extends StatefulWidget {
  final CompanionContext conversation;
  final SoftSounds sounds;
  final bool autoTalk, compact;
  final Duration interval;
  const CompanionBar({
    super.key,
    required this.conversation,
    required this.sounds,
    this.autoTalk = true,
    this.compact = false,
    this.interval = const Duration(seconds: 20),
  });
  @override
  State<CompanionBar> createState() => _CompanionBarState();
}

class _CompanionBarState extends State<CompanionBar>
    with WidgetsBindingObserver {
  final deck = CatChatter();
  final history = <CatLine>[];
  late CatLine line;
  Timer? timer;
  bool foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _next(speak: false);
    _schedule();
  }

  void _next({bool speak = true}) {
    line = deck.next(widget.conversation);
    history.add(line);
    if (history.length > 30) history.removeAt(0);
    if (speak) widget.sounds.speak(line.mood);
  }

  void _schedule() {
    timer?.cancel();
    if (!foreground || !widget.autoTalk) return;
    timer = Timer(widget.interval, () {
      if (!mounted) return;
      if ((ModalRoute.of(context)?.isCurrent ?? true) &&
          !widget.sounds.voiceBusy) {
        setState(_next);
      }
      _schedule();
    });
  }

  @override
  void didUpdateWidget(CompanionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.key != widget.conversation.key) {
      _next(speak: false);
    }
    if (oldWidget.autoTalk != widget.autoTalk ||
        oldWidget.interval != widget.interval ||
        oldWidget.conversation.key != widget.conversation.key) {
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    _schedule();
    if (!foreground) widget.sounds.stopVoice();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.sounds.stopVoice();
    super.dispose();
  }

  void _history() {
    final messages = history.reversed.toList();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Разговор с котом'),
        content: SizedBox(
          width: 560,
          height: (MediaQuery.sizeOf(context).height * .45)
              .clamp(100, 360)
              .toDouble(),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: messages.length,
            separatorBuilder: (_, _) => const Divider(height: 28),
            itemBuilder: (_, index) => Text(messages[index].text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final style = Theme.of(context).textTheme.bodyMedium!;
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14) *
        (style.height ?? 1.5);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: widget.compact ? 6 : 10,
        ),
        child: Row(
          children: [
            CatPortrait(size: widget.compact ? 30 : 42),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: _history,
                borderRadius: BorderRadius.circular(12),
                child: Semantics(
                  label:
                      'Кот-наставник. ${line.text}. Открыть историю разговора',
                  button: true,
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!widget.compact)
                        Text(
                          'Кот рядом',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      SizedBox(
                        height: lineHeight * (widget.compact ? 1 : 2),
                        child: AnimatedSwitcher(
                          duration: Duration(milliseconds: reduce ? 0 : 240),
                          child: Align(
                            key: ValueKey(line.text),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              line.text,
                              style: style,
                              maxLines: widget.compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ещё реплика',
              onPressed: () {
                setState(_next);
                _schedule();
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
