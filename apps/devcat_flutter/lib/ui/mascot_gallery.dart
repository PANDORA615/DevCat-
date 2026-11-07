import 'package:flutter/material.dart';
import '../core/mascot.dart';
import '../core/sound.dart';
import '../core/store.dart';
import 'mascot_frames.dart';
import 'cat_dialogue.dart';
import 'mascot_playground.dart';

class MascotGallery extends StatefulWidget {
  final AppStore store;
  final SoftSounds sounds;
  const MascotGallery({super.key, required this.store, required this.sounds});
  @override
  State<MascotGallery> createState() => _MascotGalleryState();
}

class _MascotGalleryState extends State<MascotGallery> {
  final loading = MascotCatalog.load();
  String appearance = 'student', state = 'idle', background = 'checker';
  bool playing = false, dialogue = false;
  int frame = 0, message = 0;
  @override
  void dispose() {
    widget.sounds.stopVoice();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Кот · образы, кадры и звук')),
    body: FutureBuilder<MascotCatalog>(
      future: loading,
      initialData: MascotCatalog.cached,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Не удалось открыть пакет кота. Основное обучение доступно.',
            ),
          );
        }
        final catalog = snapshot.data;
        if (catalog == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final clip = catalog.clip(appearance, state);
        final frames = clip == null ? 1 : (clip['frames'] as List).length;
        final color = switch (background) {
          'light' => Colors.white,
          'dark' => const Color(0xff141119),
          _ => const Color(0xffdddddd),
        };
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Новые пиксельные образы: покой, моргание, речь, радость, размышление и реакция на ошибку для каждого костюма. У ученика есть дополнительные действия. Восемь ракурсов ученика можно просмотреть по кадрам.',
            ),
            const SizedBox(height: 16),
            MascotPlayground(catalog: catalog, appearance: appearance),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: appearance,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Образ'),
              items: catalog.appearances
                  .map(
                    (a) => DropdownMenuItem<String>(
                      value: a['id'],
                      child: Text(a['title']),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                appearance = v!;
                frame = 0;
                playing = false;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: state,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Действие'),
              items: catalog.states.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value['title']),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                state = v!;
                frame = 0;
                playing = false;
              }),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final bg in {
                  'checker': 'Шахматный',
                  'light': 'Белый',
                  'dark': 'Тёмный',
                }.entries)
                  ChoiceChip(
                    label: Text(bg.value),
                    selected: background == bg.key,
                    onSelected: (_) => setState(() => background = bg.key),
                  ),
              ],
            ),
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 18),
                width: 320,
                height: 320,
                color: color,
                child: CustomPaint(
                  painter: background == 'checker'
                      ? const _Checkerboard()
                      : null,
                  child: MascotFrames(
                    key: ValueKey('$appearance:$state'),
                    appearance: appearance,
                    state: state,
                    size: 320,
                    playing: playing,
                    frame: playing ? null : frame,
                    onFrame: (index) {
                      if (playing) frame = index;
                    },
                  ),
                ),
              ),
            ),
            Text(
              clip == null
                  ? 'Клип не подготовлен. Показан статичный образ «${catalog.appearance(appearance)['title']}».'
                  : 'Кадр ${frame + 1}/$frames · ${clip['durationsMs']} мс · ${clip['loop'] == true ? 'цикл' : 'однократно'} · ${clip['productionReady'] == true ? 'сетка 128 × 128, общая опора' : 'исходный референс, ещё не нормализован'}',
              textAlign: TextAlign.center,
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              children: [
                IconButton(
                  tooltip: 'Предыдущий кадр',
                  onPressed: clip == null
                      ? null
                      : () => setState(() {
                          playing = false;
                          frame = (frame - 1) % frames;
                        }),
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                FilledButton.icon(
                  onPressed: clip == null || clip['kind'] == 'views'
                      ? null
                      : () => setState(() => playing = !playing),
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(playing ? 'Пауза' : 'Проиграть'),
                ),
                IconButton(
                  tooltip: 'Следующий кадр',
                  onPressed: clip == null
                      ? null
                      : () => setState(() {
                          playing = false;
                          frame = (frame + 1) % frames;
                        }),
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    await widget.store.set('mascotAppearance', appearance);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Образ выбран. Костюм не изменяет учебный прогресс.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Носить этот образ'),
                ),
                OutlinedButton(
                  onPressed: () => widget.store.set('mascotAppearance', 'auto'),
                  child: const Text('Эволюция по учебному уровню'),
                ),
                TextButton(
                  onPressed: () =>
                      widget.store.set('mascotAppearance', 'classic'),
                  child: const Text('Вернуть кота на книге'),
                ),
              ],
            ),
            const Divider(height: 32),
            FilledButton.tonal(
              onPressed: () => setState(() {
                dialogue = true;
                message++;
              }),
              child: const Text('Реплика: текст, рот и голос'),
            ),
            if (dialogue)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: MascotScope(
                  appearance: appearance,
                  child: CatDialogue(
                    'Давай разберём задачу вместе. Что известно на входе? Сначала запусти маленький пример, затем проверь граничный случай.',
                    key: ValueKey(message),
                    sounds: widget.sounds,
                    size: 86,
                  ),
                ),
              ),
            if (dialogue)
              TextButton(
                onPressed: () => setState(() => dialogue = false),
                child: const Text('Отменить реплику'),
              ),
            const Divider(height: 32),
            Text(
              '18 оригинальных звуков',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Прослушивание использует текущие настройки громкости и выключения звука.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in {
                  ...SoftSounds.cues.values,
                  ...SoftSounds.voiceDurations.keys,
                })
                  OutlinedButton.icon(
                    onPressed: () => widget.sounds.previewSample(id),
                    icon: const Icon(Icons.volume_up_outlined),
                    label: Text(id),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            ExpansionTile(
              title: const Text('Покрытие образов'),
              children: [
                for (final a in catalog.appearances)
                  ListTile(
                    title: Text(a['title']),
                    subtitle: Text(
                      a['id'] == 'student'
                          ? '31 клип · художественный предпросмотр'
                          : 'Статичный мастер · клипы не подготовлены',
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _Checkerboard extends CustomPainter {
  const _Checkerboard();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xffaaaaaa);
    for (var y = 0; y < size.height; y += 16) {
      for (var x = 0; x < size.width; x += 16) {
        if ((x ~/ 16 + y ~/ 16).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 16, 16),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Checkerboard oldDelegate) => false;
}
