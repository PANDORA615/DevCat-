import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/course.dart';
import '../core/store.dart';
import '../core/study.dart';
import '../core/sound.dart';
import 'git_page.dart';
import 'ide.dart';
import 'lecture.dart';
import 'study_session.dart';
import 'study_widgets.dart';
import 'workspace.dart';

class StudyHub extends StatefulWidget {
  final Course course;
  final List<Course> courses;
  final AppStore store;
  final SoftSounds sounds;
  final ValueChanged<String>? onCourseChanged;
  final ValueChanged<int>? onTopicChanged;
  const StudyHub({
    super.key,
    required this.course,
    required this.courses,
    required this.store,
    required this.sounds,
    this.onCourseChanged,
    this.onTopicChanged,
  });
  @override
  State<StudyHub> createState() => _StudyHubState();
}

class _StudyHubState extends State<StudyHub> {
  late Future<StudyCatalog> loading;
  ScrollController? scroll;
  @override
  void initState() {
    super.initState();
    loading = StudyCatalog.load();
  }

  @override
  void dispose() {
    scroll?.dispose();
    super.dispose();
  }

  Future<void> _launch(
    StudyTopic topic,
    StudyUnit unit, {
    bool review = false,
  }) async {
    widget.sounds.cue(SoundCue.open);
    widget.onTopicChanged?.call(topic.index);
    if (widget.course.id != 'git') {
      await widget.store.cursor(widget.course.id, topic.index, 0);
    }
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StudySessionPage(
          topic: topic,
          unit: unit,
          course: widget.course,
          lesson: widget.course.lessons[topic.index],
          store: widget.store,
          sounds: widget.sounds,
          review: review,
          onPractice: () => _practice(widget.course.lessons[topic.index]),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _practice(Lesson lesson) {
    final child = widget.course.id == 'git'
        ? GitPage(store: widget.store, sounds: widget.sounds)
        : ['html', 'css'].contains(widget.course.id)
        ? IdePage(
            store: widget.store,
            sounds: widget.sounds,
            language: widget.course.id,
            lesson: lesson,
          )
        : WorkspacePage(
            store: widget.store,
            sounds: widget.sounds,
            language: widget.course.id,
            course: widget.course,
            lesson: lesson,
          );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Практика в редакторе')),
          body: child,
        ),
      ),
    );
  }

  void _book(Lesson lesson) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (page) => Scaffold(
        appBar: AppBar(title: const Text('Теория с примерами')),
        body: LectureView(
          lesson: lesson,
          course: widget.course,
          store: widget.store,
          onPractice: () {
            Navigator.pop(page);
            _practice(lesson);
          },
        ),
      ),
    ),
  );

  Future<void> _goal() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Немного каждый день',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Выбери удобный темп. Он влияет только на дневную цель — доступ к занятиям не ограничивается.',
            ),
            const SizedBox(height: 16),
            for (final goal in [1, 3, 5])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StudyButton(
                  label:
                      '$goal ${goal == 1
                          ? 'ЗАНЯТИЕ'
                          : goal < 5
                          ? 'ЗАНЯТИЯ'
                          : 'ЗАНЯТИЙ'} В ДЕНЬ',
                  onPressed: () async {
                    await widget.store.set('studyDailyGoal', goal);
                    if (sheet.mounted) Navigator.pop(sheet);
                    if (mounted) setState(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );

  void _topic(StudyTopic topic, bool unlocked) {
    final ledger = StudyLedger(widget.store.progress);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                topic.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                unlocked
                    ? 'Три коротких занятия: разберись, потренируйся, примени.'
                    : 'Здесь понадобятся предыдущие темы. Пройди открытый шаг маршрута; подробную теорию можно читать уже сейчас.',
              ),
              const SizedBox(height: 18),
              for (final round in topic.rounds)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(
                      ledger.done(round)
                          ? Icons.check_rounded
                          : Icons.star_outline_rounded,
                    ),
                  ),
                  title: Text(
                    round.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${round.steps.where((s) => !s.informational).length} заданий · ${round.level == 2 && widget.course.lessons[topic.index].challenge != null ? 'с запуском кода' : 'один шаг за раз'}',
                  ),
                  trailing:
                      unlocked &&
                          (round.level == 0 ||
                              ledger.done(topic.rounds[round.level - 1]))
                      ? IconButton(
                          key: ValueKey('study-round:${round.id}'),
                          tooltip: ledger.done(round)
                              ? 'Повторить занятие'
                              : 'Начать занятие',
                          icon: Icon(
                            ledger.done(round)
                                ? Icons.replay_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          onPressed: () {
                            Navigator.pop(sheet);
                            _launch(topic, round, review: ledger.done(round));
                          },
                        )
                      : const Icon(Icons.lock_outline_rounded),
                ),
              const SizedBox(height: 14),
              if (unlocked)
                StudyButton(
                  label: ledger.levels(topic) == 3
                      ? 'ПОВТОРИТЬ ТЕМУ'
                      : 'НАЧАТЬ ЗАНЯТИЕ',
                  onPressed: () {
                    Navigator.pop(sheet);
                    final next = topic.rounds.firstWhere(
                      (r) => !ledger.done(r),
                      orElse: () => topic.rounds.last,
                    );
                    _launch(topic, next, review: ledger.done(next));
                  },
                ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  _book(widget.course.lessons[topic.index]);
                },
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Подробная теория и примеры'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  _practice(widget.course.lessons[topic.index]);
                },
                icon: const Icon(Icons.code_rounded),
                label: const Text('Открыть практику в IDE'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<StudyCatalog>(
    future: loading,
    initialData: StudyCatalog.cached,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не получилось открыть программу занятий.'),
              TextButton(
                onPressed: () => setState(() => loading = StudyCatalog.load()),
                child: const Text('Попробовать ещё раз'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final topics = snapshot.data!.forCourse(widget.course);
      final ledger = StudyLedger(widget.store.progress);
      final active = ledger.firstIncomplete(topics);
      final goal = widget.store.setting<int>('studyDailyGoal', 3).clamp(1, 5);
      final nextTopic = topics[active];
      final nextUnit = nextTopic.rounds.firstWhere(
        (r) => !ledger.done(r),
        orElse: () => nextTopic.rounds.last,
      );
      final entries = <Object>[];
      var chapter = '';
      for (final topic in topics) {
        if (topic.chapter != chapter) {
          entries.add(topic.chapter);
          chapter = topic.chapter;
        }
        entries.add(topic);
      }
      scroll ??= ScrollController(
        initialScrollOffset: active <= 1 ? 0 : max(0, active * 160.0 - 80),
      );
      final scheme = Theme.of(context).colorScheme;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Row(
              children: [
                Expanded(
                  child: widget.onCourseChanged == null
                      ? Text(
                          widget.course.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: widget.course.id,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(18),
                            items: widget.courses
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(
                                      c.name,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) widget.onCourseChanged!(value);
                            },
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                StudyMetric(
                  Icons.local_fire_department_rounded,
                  '${ledger.streak}',
                  'дней подряд',
                  color: Colors.deepOrange,
                ),
                const SizedBox(width: 18),
                StudyMetric(Icons.bolt_rounded, '${ledger.xp}', 'XP'),
                IconButton(
                  onPressed: () => _book(widget.course.lessons[active]),
                  icon: const Icon(Icons.menu_book_rounded),
                  tooltip: 'Подробный учебник',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              itemCount: entries.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 660),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 18),
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: scheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        value: (ledger.today / goal).clamp(
                                          0,
                                          1,
                                        ),
                                        strokeWidth: 5,
                                        backgroundColor:
                                            scheme.surfaceContainerHighest,
                                      ),
                                      Icon(
                                        ledger.today >= goal
                                            ? Icons.check_rounded
                                            : Icons.flag_rounded,
                                        color: scheme.primary,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Твоя цель на сегодня',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                        ),
                                      ),
                                      Text(
                                        '${ledger.today} из $goal коротких занятий',
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _goal,
                                  icon: const Icon(Icons.tune_rounded),
                                  tooltip: 'Настроить дневную цель',
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            StudyButton(
                              key: const ValueKey('study-start'),
                              label: 'ПРОДОЛЖИТЬ ОБУЧЕНИЕ',
                              icon: Icons.play_arrow_rounded,
                              onPressed: () => _launch(
                                nextTopic,
                                nextUnit,
                                review: ledger.done(nextUnit),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              '${nextTopic.title} · ${nextUnit.title}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                if (index == 1) {
                  final due = topics.where(ledger.due).toList();
                  if (due.isEmpty) return const SizedBox.shrink();
                  final topic = due.first;
                  final unit = ledger.reviewUnit(topic);
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 660),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: StudyButton(
                          label: 'ПОВТОРЕНИЕ · ${due.length}',
                          icon: Icons.replay_rounded,
                          onPressed: () => _launch(topic, unit, review: true),
                        ),
                      ),
                    ),
                  );
                }
                final item = entries[index - 2];
                if (item is String) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 660),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(0, 12, 0, 10),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Color.lerp(
                                scheme.primary,
                                Colors.black,
                                .2,
                              )!,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.flag_rounded, color: Colors.white),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                item,
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final topic = item as StudyTopic;
                final level = ledger.levels(topic);
                final unlocked = topic.index <= active;
                return Center(
                  child: SizedBox(
                    width: 480,
                    child: _PathNode(
                      topic: topic,
                      levels: level,
                      unlocked: unlocked,
                      active: topic.index == active && level < 3,
                      onTap: () => _topic(topic, unlocked),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

class _PathNode extends StatelessWidget {
  final StudyTopic topic;
  final int levels;
  final bool unlocked, active;
  final VoidCallback onTap;
  const _PathNode({
    required this.topic,
    required this.levels,
    required this.unlocked,
    required this.active,
    required this.onTap,
  });
  static double offset(int index) =>
      const [0.0, -52.0, -82.0, -52.0, 0.0, 52.0, 82.0, 52.0][index % 8];
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = unlocked ? scheme.primary : scheme.surfaceContainerHighest;
    return Semantics(
      button: true,
      label:
          '${topic.index + 1}. ${topic.title}. $levels из 3 ступеней. ${unlocked ? 'Открыто' : 'Впереди'}',
      child: SizedBox(
        height: 164,
        child: LayoutBuilder(
          builder: (context, box) {
            final dx = offset(topic.index) * min(1, box.maxWidth / 430);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PathLine(
                      offset(max(0, topic.index - 1)) *
                          min(1, box.maxWidth / 430),
                      dx,
                      unlocked
                          ? scheme.primary.withValues(alpha: .35)
                          : scheme.outlineVariant,
                    ),
                  ),
                ),
                Positioned(
                  top: 19,
                  left: box.maxWidth / 2 + dx - 46,
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (active || levels > 0)
                          SizedBox(
                            width: 90,
                            height: 90,
                            child: CircularProgressIndicator(
                              value: levels / 3,
                              strokeWidth: 5,
                              color: scheme.primary,
                              backgroundColor: scheme.outlineVariant,
                            ),
                          ),
                        Container(
                          width: 73,
                          height: 73,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color.lerp(color, Colors.black, .22)!,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onTap,
                              child: Icon(
                                !unlocked
                                    ? Icons.lock_rounded
                                    : levels == 3
                                    ? Icons.check_rounded
                                    : Icons.star_rounded,
                                size: 37,
                                color: unlocked
                                    ? scheme.onPrimary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        if (active)
                          Positioned(
                            top: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.primary,
                                  width: 2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                child: Text(
                                  levels == 0 ? 'НАЧНИ' : 'ДАЛЬШЕ',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 120,
                  left: max(0, box.maxWidth / 2 + dx - 130),
                  right: max(0, box.maxWidth / 2 - dx - 130),
                  child: GestureDetector(
                    onTap: onTap,
                    child: ColoredBox(
                      color: scheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          topic.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PathLine extends CustomPainter {
  final double previous, current;
  final Color color;
  _PathLine(this.previous, this.current, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final path = Path()
      ..moveTo(center + previous, 0)
      ..cubicTo(
        center + previous,
        24,
        center + current,
        30,
        center + current,
        65,
      )
      ..lineTo(center + current, size.height);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 14) {
        canvas.drawPath(
          metric.extractPath(start, min(start + 5, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PathLine old) =>
      old.previous != previous || old.current != current || old.color != color;
}

class GitStudyHub extends StatefulWidget {
  final AppStore store;
  final SoftSounds sounds;
  const GitStudyHub({super.key, required this.store, required this.sounds});
  @override
  State<GitStudyHub> createState() => _GitStudyHubState();
}

class _GitStudyHubState extends State<GitStudyHub> {
  late final course = rootBundle
      .loadString('assets/content/git_course.json')
      .then((s) => Course(jsonDecode(s)));
  @override
  Widget build(BuildContext context) => FutureBuilder<Course>(
    future: course,
    builder: (_, snapshot) => snapshot.hasData
        ? StudyHub(
            course: snapshot.data!,
            courses: [snapshot.data!],
            store: widget.store,
            sounds: widget.sounds,
          )
        : const Center(child: CircularProgressIndicator()),
  );
}
