import 'package:flutter/material.dart';
import '../core/mascot.dart';
import '../core/sound.dart';
import '../core/store.dart';
import 'cat_actor.dart';

/// Review the actual archive assets without pretending missing clips exist.
class MascotGallery extends StatefulWidget {
  final AppStore store;
  final SoftSounds sounds;
  const MascotGallery({super.key, required this.store, required this.sounds});
  @override
  State<MascotGallery> createState() => _MascotGalleryState();
}

class _MascotGalleryState extends State<MascotGallery> {
  late final controller = CatAnimationController(
    appearanceId: MascotCatalog.selected(widget.store),
  );
  String action = 'idle';
  Color background = const Color(0xffded6ef);
  @override
  void dispose() {
    controller.dispose();
    widget.sounds.stopVoice();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Галерея DevCat')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'У Ученика — 31 действие. У остальных образов — 6 базовых анимаций. Созданные кадры проходят визуальную проверку; отсутствующие действия отмечены отдельно.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: controller.appearanceId,
          decoration: const InputDecoration(
            labelText: 'Внешность для просмотра',
          ),
          items: MascotCatalog.appearances
              .map((a) => DropdownMenuItem(value: a.id, child: Text(a.title)))
              .toList(),
          onChanged: (id) {
            if (id != null) setState(() => controller.selectAppearance(id));
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: action,
          decoration: const InputDecoration(labelText: 'Действие / эмоция'),
          items: MascotCatalog.clips.values
              .map(
                (c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(
                    '${c.title} · ${c.id}${MascotCatalog.clipsFor(controller.appearanceId).containsKey(c.id) ? '' : ' · нет кадров'}',
                  ),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id != null) {
              setState(() {
                action = id;
                controller.play(id, force: true);
              });
            }
          },
        ),
        const SizedBox(height: 16),
        ColoredBox(
          color: background,
          child: Center(child: CatActor(size: 240, controller: controller)),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final color in [
              Colors.white,
              Colors.black,
              const Color(0xffded6ef),
              Colors.teal,
            ])
              IconButton(
                onPressed: () => setState(() => background = color),
                tooltip: 'Фон ${color.toARGB32().toRadixString(16)}',
                icon: Icon(Icons.circle, color: color),
              ),
          ],
        ),
        ListenableBuilder(
          listenable: controller,
          builder: (_, _) => Text(
            controller.diagnostic ??
                (controller.hasClip
                    ? '${controller.state}: кадр ${controller.frame + 1}/${controller.clip.frames.length} · ${controller.clip.durationMs} мс'
                    : 'Статичный образ · клипы не подготовлены'),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: () =>
                  setState(() => controller.play(action, force: true)),
              child: const Text('Играть'),
            ),
            OutlinedButton(
              onPressed: controller.pause,
              child: const Text('Пауза'),
            ),
            OutlinedButton(
              onPressed: controller.resume,
              child: const Text('Продолжить'),
            ),
            OutlinedButton(
              onPressed: controller.cancel,
              child: const Text('Стоп'),
            ),
            IconButton(
              onPressed: () => controller.step(-1),
              tooltip: 'Предыдущий кадр',
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              onPressed: () => controller.step(1),
              tooltip: 'Следующий кадр',
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '8 ракурсов ученика',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final name in [
              'front',
              'front_left',
              'left',
              'back_three_quarter',
              'back',
              'front_right',
              'right',
              'front_sitting',
            ])
              SizedBox(
                width: 110,
                child: Column(
                  children: [
                    Image.asset(
                      'assets/mascot/views/student/$name.png',
                      height: 100,
                      cacheHeight: 200,
                      filterQuality: FilterQuality.none,
                    ),
                    Text(name),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '18 оригинальных звуков',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final name in {
          ...SoftSounds.cues.values,
          ...SoftSounds.voiceDurations.keys,
        })
          ListTile(
            title: Text(name),
            trailing: IconButton(
              tooltip: 'Прослушать $name',
              icon: const Icon(Icons.play_arrow),
              onPressed: () => widget.sounds.preview(name),
            ),
          ),
      ],
    ),
  );
}

class MascotSettings extends StatelessWidget {
  final AppStore store;
  final SoftSounds sounds;
  const MascotSettings({super.key, required this.store, required this.sounds});
  @override
  Widget build(BuildContext context) {
    final level = MascotCatalog.levelFor(store);
    final costume = store.setting('catCostume', 'none');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Кот DevCat · уровень $level',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          'Эволюция: ${MascotCatalog.evolution(level).title}. Уровень растёт за учебный XP: 100 XP за уровень.',
        ),
        const SizedBox(height: 12),
        Center(child: CatActor(size: 140)),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue:
              MascotCatalog.appearances.any(
                (a) => a.id == costume && a.kind == 'costume',
              )
              ? costume
              : 'none',
          decoration: const InputDecoration(labelText: 'Костюм'),
          items: [
            const DropdownMenuItem(
              value: 'none',
              child: Text('По уровню · без костюма'),
            ),
            ...MascotCatalog.appearances
                .where((a) => a.kind == 'costume')
                .map(
                  (a) => DropdownMenuItem(value: a.id, child: Text(a.title)),
                ),
          ],
          onChanged: (id) {
            if (id != null) store.set('catCostume', id);
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.collections_outlined),
          label: const Text('Галерея кота'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MascotGallery(store: store, sounds: sounds),
            ),
          ),
        ),
      ],
    );
  }
}
