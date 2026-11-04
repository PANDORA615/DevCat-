import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/sound.dart';
import '../core/mascot.dart';
import 'mascot_frames.dart';

class CatActor extends StatefulWidget {
  final double size;
  final CatMood mood;
  final bool? talking;
  const CatActor({
    super.key,
    required this.size,
    this.mood = CatMood.greeting,
    this.talking,
  });
  @override
  State<CatActor> createState() => _CatActorState();
}

class _CatActorState extends State<CatActor>
    with SingleTickerProviderStateMixin {
  static Future<ui.Image>? atlas;
  late final AnimationController animation;
  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    atlas ??= _load();
  }

  static Future<ui.Image> _load() async {
    final data = await rootBundle.load('assets/branding/companion_sheet.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _talk();
  }

  @override
  void didUpdateWidget(CatActor old) {
    super.didUpdateWidget(old);
    if (old.talking != widget.talking) _talk();
  }

  void _talk() {
    animation.stop();
    animation.value = 0;
    if (widget.talking != true || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    animation.repeat(reverse: true);
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = MascotScope.of(context);
    if (appearance != 'classic') {
      final state = widget.talking == true
          ? 'talk'
          : switch (widget.mood) {
              CatMood.greeting => 'idle',
              CatMood.celebration => 'happy',
              CatMood.explaining => 'explaining',
              CatMood.thinking => 'thinking',
              CatMood.warning => 'failure',
              CatMood.encouragement => 'thoughtful',
            };
      return MascotFrames(
        appearance: appearance,
        state: state,
        size: widget.size,
      );
    }
    return Semantics(
      label: 'Кот на учебнике: ${widget.mood.name}',
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size * .85,
        child: FutureBuilder<ui.Image>(
          future: atlas,
          builder: (_, snapshot) => snapshot.hasData
              ? AnimatedBuilder(
                  animation: animation,
                  builder: (_, _) => CustomPaint(
                    painter: _CatFrame(
                      snapshot.data!,
                      widget.mood,
                      animation.isAnimating && animation.value > .12,
                    ),
                  ),
                )
              : Image.asset(
                  'assets/branding/devcat_book.png',
                  filterQuality: FilterQuality.none,
                ),
        ),
      ),
    );
  }
}

class _CatFrame extends CustomPainter {
  final ui.Image image;
  final CatMood mood;
  final bool mouth;
  _CatFrame(this.image, this.mood, this.mouth);
  @override
  void paint(Canvas canvas, Size size) {
    final index = switch (mood) {
      CatMood.greeting => 0,
      CatMood.celebration => 1,
      CatMood.explaining => 2,
      CatMood.thinking => 3,
      CatMood.warning => 4,
      CatMood.encouragement => 5,
    };
    final cell = index * 2 + (mouth ? 1 : 0);
    final w = image.width / 4, h = image.height / 3;
    final src = Rect.fromLTWH((cell % 4) * w, (cell ~/ 4) * h, w, h);
    final target = applyBoxFit(BoxFit.contain, Size(w, h), size).destination;
    canvas.drawImageRect(
      image,
      src,
      Alignment.center.inscribe(target, Offset.zero & size),
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_CatFrame old) =>
      old.image != image || old.mood != mood || old.mouth != mouth;
}
