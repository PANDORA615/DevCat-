import 'dart:math';
import 'package:flutter/material.dart';
import '../core/course.dart';
import '../core/store.dart';
import '../core/sound.dart';
import 'widgets.dart';
import 'workspace.dart';
import 'settings.dart';
import 'git_page.dart';
import 'lecture.dart';
import 'ide.dart';
import '../core/cat_chatter.dart';
import 'companion.dart';

class DevCatShell extends StatefulWidget {
  final AppStore store;
  final List<Course> courses;
  final SoftSounds sounds;
  const DevCatShell({
    super.key,
    required this.store,
    required this.courses,
    required this.sounds,
  });
  @override
  State<DevCatShell> createState() => _DevCatShellState();
}

class _DevCatShellState extends State<DevCatShell> {
  int page = 0;
  bool reading = true;
  late String language;
  int lesson = 0, seed = 0;
  static const labels = [
    'Главная',
    'Языки',
    'Git / GitHub',
    'DevCat IDE',
    'Справочник',
    'Прогресс',
    'Настройки',
  ];
  static const icons = [
    Icons.home_rounded,
    Icons.school_rounded,
    Icons.account_tree_rounded,
    Icons.code_rounded,
    Icons.auto_stories_rounded,
    Icons.insights_rounded,
    Icons.tune_rounded,
  ];
  @override
  void initState() {
    super.initState();
    _resume();
  }

  void _resume() {
    final cursor = widget.store.progress.latestCursor;
    language =
        cursor?['language'] ?? widget.store.setting('language', 'python');
    if (!languageNames.containsKey(language)) language = 'python';
    lesson = (cursor?['lesson'] ?? 0).clamp(
      0,
      widget.courses.firstWhere((c) => c.id == language).lessons.length - 1,
    );
    seed = cursor?['seed'] ?? 0;
  }

  Course get course => widget.courses.firstWhere((c) => c.id == language);
  void openCourse(String id, {int? index, int? generated}) {
    setState(() {
      if (language != id) {
        lesson = 0;
        seed = 0;
      }
      language = id;
      lesson = index ?? lesson;
      seed = generated ?? seed;
      page = 1;
      reading = seed == 0;
    });
    widget.sounds.cue(SoundCue.navigation);
    widget.store.cursor(language, lesson, seed);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.setting('onboarded', false)) return _onboarding(context);
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final reduce = MediaQuery.of(context).disableAnimations;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final scheme = Theme.of(context).colorScheme;
    final content = switch (page) {
      0 => _home(context),
      1 => _courses(context),
      2 => GitPage(store: widget.store, sounds: widget.sounds),
      3 => IdePage(
        key: const ValueKey('ide'),
        store: widget.store,
        language: language,
        sounds: widget.sounds,
      ),
      4 => ReferencePage(courses: widget.courses),
      5 => _progress(context),
      _ => SettingsPage(
        store: widget.store,
        sounds: widget.sounds,
        onSynced: () => setState(_resume),
      ),
    };
    final body = Column(
      children: [
        if (!keyboard)
          Padding(
            padding: EdgeInsets.fromLTRB(
              wide ? 32 : 20,
              18,
              wide ? 32 : 20,
              16,
            ),
            child: Row(
              children: [
                if (!wide) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: DevCatLogo(size: 34),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  wide ? 'Твоя мастерская  /  ${labels[page]}' : 'DevCat',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                const StatusBadge(Icons.offline_bolt_rounded, 'Локально'),
              ],
            ),
          ),
        if (widget.store.storageWarning != null)
          MaterialBanner(
            content: Text(widget.store.storageWarning!),
            actions: [
              TextButton(
                onPressed: () =>
                    setState(() => widget.store.storageWarning = null),
                child: const Text('Понятно'),
              ),
            ],
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: reduce ? 0 : 240),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: KeyedSubtree(key: ValueKey(page), child: content),
          ),
        ),
        if (widget.store.setting('cat', true))
          CompanionBar(
            key: const ValueKey('persistent-companion'),
            sounds: widget.sounds,
            autoTalk: widget.store.setting('catChatter', true),
            interval: Duration(
              seconds: widget.store
                  .setting<num>('catChatterSeconds', 20)
                  .toInt()
                  .clamp(10, 120)
                  .toInt(),
            ),
            compact: keyboard || MediaQuery.sizeOf(context).height < 550,
            conversation: CompanionContext(
              switch (page) {
                0 => CompanionPlace.home,
                1 => reading ? CompanionPlace.lesson : CompanionPlace.practice,
                2 => CompanionPlace.git,
                3 => CompanionPlace.ide,
                4 => CompanionPlace.reference,
                5 => CompanionPlace.progress,
                _ => CompanionPlace.settings,
              },
              title: page == 1 ? course.lessons[lesson].title : '',
              language: page == 1 ? language : '',
            ),
          ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 238,
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.fromLTRB(12, 22, 12, 18),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: DevCatLogo(size: 44),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'DevCat',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...List.generate(
                      labels.length,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Material(
                          color: page == i
                              ? scheme.secondaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: () {
                              widget.sounds.cue(SoundCue.navigation);
                              setState(() => page = i);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              child: Row(
                                children: [
                                  Icon(icons[i], size: 21),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      labels[i],
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: page == i
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'В своём темпе.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Без сети. Без спешки.\nС маленьким помощником.',
                            style: TextStyle(fontSize: 12, height: 1.6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: wide || keyboard
          ? null
          : NavigationBar(
              selectedIndex: switch (page) {
                0 => 0,
                1 || 2 || 4 => 1,
                3 => 2,
                5 => 3,
                _ => 4,
              },
              onDestinationSelected: (i) {
                widget.sounds.cue(SoundCue.navigation);
                setState(() => page = [0, 1, 3, 5, 6][i]);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Главная',
                ),
                NavigationDestination(
                  icon: Icon(Icons.school_outlined),
                  label: 'Учиться',
                ),
                NavigationDestination(
                  icon: Icon(Icons.code_rounded),
                  label: 'Код',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_rounded),
                  label: 'Прогресс',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_rounded),
                  label: 'Ещё',
                ),
              ],
            ),
    );
  }

  Widget _onboarding(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CatPortrait(size: 170),
                const SizedBox(height: 28),
                Text(
                  'Привет. Я DevCat.',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 14),
                Text(
                  'Давай научимся создавать.\nПо одному понятному шагу за раз.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Уроки, задания и твой прогресс хранятся на устройстве. Аккаунт не нужен. Синхронизацию с личным хранилищем можно подключить позже.',
                ),
                const SizedBox(height: 28),
                const Text(
                  'С чего начнём?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: widget.courses
                      .map(
                        (c) => ChoiceChip(
                          label: Text(c.name),
                          selected: language == c.id,
                          onSelected: (_) => setState(() => language = c.id),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () async {
                    await widget.store.set('language', language);
                    await widget.store.set('onboarded', true);
                    if (mounted) setState(() => page = 0);
                  },
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Начать в своём темпе'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '0.1 · Офлайн-мастерская · Открытый исходный код',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _home(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final solved = widget.store.progress.solved.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 30),
      children: [
        const PageHeading(
          'Немного кода. Много открытий.',
          'Твоё место, чтобы пробовать, ошибаться и расти.',
          eyebrow: 'РАДЫ ТЕБЯ ВИДЕТЬ',
        ),
        Panel(
          color: scheme.primaryContainer,
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StatusBadge(
                        Icons.eco_rounded,
                        'МАЛЕНЬКИЙ ШАГ СЕГОДНЯ',
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Продолжим с ${course.name}?',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onPrimaryContainer,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        course.lessons[lesson].title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Один урок, немного практики — и ты уже дальше.',
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => setState(() => page = 1),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Продолжить обучение'),
                      ),
                    ],
                  ),
                ),
                if (box.maxWidth > 650)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: CatPortrait(size: 210),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final cards = [
              _stat(
                context,
                Icons.check_circle_outline_rounded,
                '$solved',
                'решённых задач',
              ),
              _stat(context, Icons.layers_outlined, '8 + Git', 'направлений'),
              _stat(
                context,
                Icons.cloud_off_rounded,
                'Без сети',
                'работает обучение',
              ),
            ];
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: cards
                  .map(
                    (c) => SizedBox(
                      width: box.maxWidth > 700
                          ? (box.maxWidth - 32) / 3
                          : box.maxWidth,
                      child: c,
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 30),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Выбери направление',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton(
              onPressed: () => setState(() => page = 4),
              child: const Text('Справочник'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth > 750
                ? (box.maxWidth - 32) / 3
                : box.maxWidth > 470
                ? (box.maxWidth - 16) / 2
                : box.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: widget.courses
                  .map(
                    (c) =>
                        SizedBox(width: width, child: _courseCard(context, c)),
                  )
                  .toList(),
            );
          },
        ),
        if (widget.store.setting('cat', true)) ...[
          const SizedBox(height: 24),
          CatMessage(
            'Не обязательно понимать всё сразу. Запусти код, посмотри на результат и попробуй ещё раз. Я рядом.',
            mood: CatMood.greeting,
            reducedMotion: MediaQuery.of(context).disableAnimations,
          ),
        ],
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) => Panel(
    padding: const EdgeInsets.all(22),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _courseCard(BuildContext context, Course c) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(26),
    child: InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () => openCourse(c.id),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    c.id == 'python'
                        ? 'Py'
                        : c.id == 'javascript'
                        ? 'JS'
                        : c.id == 'csharp'
                        ? 'C#'
                        : c.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.north_east_rounded, size: 18),
              ],
            ),
            const SizedBox(height: 18),
            Text(c.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(c.subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Text(
              '${c.version} · ${c.lessons.length} лекций и практика',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _directory() async {
    String query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .85,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      labelText: '${course.name}: поиск по 40 лекциям',
                    ),
                    onChanged: (value) =>
                        update(() => query = value.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: course.lessons.length,
                    itemBuilder: (_, i) {
                      final item = course.lessons[i];
                      if (!'${item.title} ${item.chapter}'
                          .toLowerCase()
                          .contains(query)) {
                        return const SizedBox.shrink();
                      }
                      return ListTile(
                        selected: lesson == i,
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(item.title),
                        subtitle: Text('${item.chapter} · ${item.minutes} мин'),
                        trailing: Icon(
                          item.challenge != null
                              ? Icons.fact_check_outlined
                              : Icons.construction_rounded,
                        ),
                        onTap: () {
                          Navigator.pop(sheet);
                          openCourse(language, index: i, generated: 0);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _courses(BuildContext context) => Column(
    children: [
      if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              ...widget.courses.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c.name),
                    selected: language == c.id,
                    onSelected: (_) => openCourse(c.id),
                  ),
                ),
              ),
              ActionChip(
                label: const Text('Git / GitHub'),
                onPressed: () => setState(() => page = 2),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                onPressed: lesson > 0
                    ? () =>
                          openCourse(language, index: lesson - 1, generated: 0)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Предыдущая лекция',
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _directory,
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text(
                    '${lesson + 1}/${course.lessons.length}. ${course.lessons[lesson].title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                onPressed: lesson + 1 < course.lessons.length
                    ? () =>
                          openCourse(language, index: lesson + 1, generated: 0)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Следующая лекция',
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.auto_stories_outlined),
                    label: Text('Лекция'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.code_rounded),
                    label: Text('Практика'),
                  ),
                ],
                selected: {reading && seed == 0},
                onSelectionChanged: (value) {
                  widget.sounds.cue(SoundCue.navigation);
                  setState(() {
                    reading = value.first;
                    if (reading) seed = 0;
                  });
                },
              ),
              const SizedBox(width: 12),
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Задание от кота'),
                onPressed: () => openCourse(
                  language,
                  index: lesson,
                  generated: 1 + Random.secure().nextInt(1000000000),
                ),
              ),
            ],
          ),
        ),
      ],
      Expanded(
        child: reading && seed == 0
            ? LectureView(
                key: ValueKey('lecture:$language:$lesson'),
                lesson: course.lessons[lesson],
                course: course,
                store: widget.store,
                onPractice: () => setState(() => reading = false),
              )
            : WorkspacePage(
                key: ValueKey('$language:$lesson:$seed'),
                store: widget.store,
                language: language,
                sounds: widget.sounds,
                course: course,
                lesson: course.lessons[lesson],
                seed: seed,
              ),
      ),
    ],
  );
  Widget _progress(BuildContext context) {
    final progress = widget.store.progress;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const PageHeading(
          'Каждый шаг считается.',
          'Здесь только результаты реальных проверок. Без штрафов за паузы.',
          eyebrow: 'ТВОЙ ПРОГРЕСС',
        ),
        _stat(
          context,
          Icons.task_alt_rounded,
          '${progress.solved.length}',
          'уникальных задач решено',
        ),
        const SizedBox(height: 18),
        ...widget.courses.map((c) {
          final count = progress.solved
              .where((id) => id.startsWith('${c.id}.'))
              .length;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('$count решено'),
                  const SizedBox(width: 16),
                  FilledButton.tonal(
                    onPressed: () => openCourse(c.id),
                    child: const Text('Учиться'),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        Text(
          'Последние попытки',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        if (progress.attempts.isEmpty)
          const Text('Первая попытка впереди. Даже ошибка — полезный шаг.'),
        ...(progress.attempts.values.toList()..sort(
              (a, b) => (b['updated'] as int).compareTo(a['updated'] as int),
            ))
            .take(20)
            .map(
              (a) => ListTile(
                leading: Icon(
                  a['passed']
                      ? Icons.check_circle_outline_rounded
                      : Icons.refresh_rounded,
                ),
                title: Text(a['task']),
                subtitle: Text(
                  DateTime.fromMillisecondsSinceEpoch(
                    a['updated'],
                  ).toLocal().toString().split('.').first,
                ),
                trailing: Text(a['passed'] ? 'Решено' : 'Попытка'),
              ),
            ),
      ],
    );
  }
}

class ReferencePage extends StatefulWidget {
  final List<Course> courses;
  const ReferencePage({super.key, required this.courses});
  @override
  State<ReferencePage> createState() => _ReferencePageState();
}

class _ReferencePageState extends State<ReferencePage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const PageHeading(
          'Знания под рукой.',
          'Лекции, примеры и типичные ошибки. Доступны без сети.',
          eyebrow: 'СПРАВОЧНИК',
        ),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Например: Python, цикл, типы, JOIN',
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 22),
        ...widget.courses.expand(
          (c) => c.lessons
              .where(
                (l) =>
                    '${c.name} ${l.title} ${l.theory} ${l.mistakes.join(' ')}'
                        .toLowerCase()
                        .contains(q),
              )
              .map(
                (l) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ExpansionTile(
                    title: Text('${c.name} · ${l.title}'),
                    subtitle: Text(l.chapter),
                    childrenPadding: const EdgeInsets.all(20),
                    children: [
                      SelectableText(
                        l.theory,
                        style: const TextStyle(height: 1.7),
                      ),
                      const SizedBox(height: 12),
                      ...l.examples.map(
                        (e) => SelectableText(
                          e,
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SelectableText('Документация: ${c.source}'),
                    ],
                  ),
                ),
              ),
        ),
      ],
    );
  }
}
