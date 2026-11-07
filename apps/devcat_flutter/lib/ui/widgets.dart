import 'package:flutter/material.dart';
import '../core/sound.dart';
import 'cat_actor.dart';
import 'speech_text.dart';

/// The supplied v5 application icon retains its original brand colors.
class DevCatLogo extends StatelessWidget {
  final double size;
  const DevCatLogo({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Логотип DevCat',
    image: true,
    child: Image.asset(
      'assets/branding/icon.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.none,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
    shape:
        Theme.of(context).cardTheme.shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    child: Padding(padding: padding, child: child),
  );
}

class PageHeading extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final Widget? trailing;
  const PageHeading(
    this.title,
    this.subtitle, {
    super.key,
    this.eyebrow = 'DEVCAT',
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 16,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
        ?trailing,
      ],
    ),
  );
}

class StatusBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  const StatusBadge(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    ),
  );
}

class CatPortrait extends StatelessWidget {
  final double size;
  final CatMood mood;
  final String? speech;
  const CatPortrait({
    super.key,
    this.size = 150,
    this.mood = CatMood.greeting,
    this.speech,
  });
  @override
  Widget build(BuildContext context) =>
      CatActor(size: size, mood: mood, speech: speech);
}

class CatMessage extends StatefulWidget {
  final String text;
  final bool reducedMotion;
  final CatMood mood;
  const CatMessage(
    this.text, {
    super.key,
    this.reducedMotion = false,
    this.mood = CatMood.explaining,
  });
  @override
  State<CatMessage> createState() => _CatMessageState();
}

class _CatMessageState extends State<CatMessage> {
  bool skip = false;
  @override
  void didUpdateWidget(CatMessage old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) skip = false;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CatActor(
          size: 66,
          mood: widget.mood,
          speech: skip ? null : widget.text,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: widget.text,
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Кот-наставник',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                SpeechText(
                  text: widget.text,
                  mood: widget.mood,
                  instant: skip || widget.reducedMotion,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: () {
            SoundScope.of(context)?.stopVoice();
            setState(() => skip = true);
          },
          icon: const Icon(Icons.fast_forward_rounded),
          tooltip: 'Показать реплику целиком',
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    ) ??
    false;
