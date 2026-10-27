import 'dart:async';
import 'package:flutter/material.dart';
import '../core/course.dart';
import '../core/store.dart';
import '../core/sound.dart';
import 'widgets.dart';

class LectureView extends StatefulWidget {
  final Lesson lesson;
  final Course course;
  final AppStore store;
  final VoidCallback onPractice;
  const LectureView({
    super.key,
    required this.lesson,
    required this.course,
    required this.store,
    required this.onPractice,
  });
  @override
  State<LectureView> createState() => _LectureViewState();
}

class _LectureViewState extends State<LectureView> with WidgetsBindingObserver {
  Timer? saveTimer;
  void _positionChanged() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _savePosition);
  }

  void _savePosition() {
    if (scroll.hasClients) {
      widget.store
          .draft('reading.${widget.lesson.id}', scroll.offset.toString())
          .catchError((_) {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      saveTimer?.cancel();
      _savePosition();
    }
  }

  final scroll = ScrollController();
  final Set<int> checked = {};
  final Set<int> answers = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(_positionChanged);
    final review = widget.store.progress.draftsFor(
      'review.${widget.lesson.id}',
    );
    if (review.isNotEmpty) {
      for (final part in (review.first['text'] as String).split(',')) {
        final index = int.tryParse(part);
        if (index != null) checked.add(index);
      }
    }
    final saved = widget.store.progress.draftsFor(
      'reading.${widget.lesson.id}',
    );
    if (saved.isNotEmpty) {
      final value = double.tryParse(saved.first['text']);
      if (value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) {
            scroll.jumpTo(value.clamp(0, scroll.position.maxScrollExtent));
          }
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    saveTimer?.cancel();
    scroll.removeListener(_positionChanged);
    if (scroll.hasClients) {
      widget.store
          .draft('reading.${widget.lesson.id}', scroll.offset.toString())
          .catchError((_) {});
    }
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final size = widget.store.setting<num>('readingSize', 18).toDouble();
    final width = widget.store.setting<num>('readingWidth', 800).toDouble();
    final spacing = widget.store.setting<num>('readingHeight', 1.8).toDouble();
    return SelectionArea(
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.course.name} · ${lesson.chapter}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    lesson.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      StatusBadge(
                        Icons.schedule_rounded,
                        '${lesson.minutes} мин с практикой',
                      ),
                      StatusBadge(
                        Icons.offline_bolt_rounded,
                        'Полностью офлайн',
                      ),
                      StatusBadge(
                        lesson.challenge != null
                            ? Icons.fact_check_outlined
                            : Icons.construction_rounded,
                        lesson.challenge != null
                            ? 'Тесты на код'
                            : 'Проектная работа',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (lesson.photo.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/content/${lesson.photo}',
                        height: 240,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lesson.photoCaption,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                  ],
                  Panel(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'План занятия',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        ...lesson.sections.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('• ${s['heading']}'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  ...lesson.sections.expand(
                    (s) => [
                      Text(
                        s['heading'],
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        s['text'] ?? '',
                        style: TextStyle(
                          fontSize: size,
                          height: spacing,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (s['code'] != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Panel(
                            padding: const EdgeInsets.all(18),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SelectableText(
                                s['code'],
                                style: TextStyle(
                                  fontFamily: 'JetBrainsMono',
                                  fontSize: (size - 3).clamp(12, 24),
                                  height: 1.65,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (s['diagram'] != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: ConceptDiagram(s['diagram']),
                        ),
                      const SizedBox(height: 28),
                    ],
                  ),
                  Text(
                    'Вопросы для самопроверки',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(
                    lesson.questions.length,
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Panel(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}. ${lesson.questions[i]}',
                              style: TextStyle(
                                fontSize: size,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextFormField(
                              initialValue:
                                  widget.store.progress
                                          .draftsFor('answer.${lesson.id}.$i')
                                          .firstOrNull?['text']
                                      as String?,
                              maxLines: 3,
                              minLines: 1,
                              decoration: const InputDecoration(
                                hintText:
                                    'Сначала сформулируй ответ своими словами',
                              ),
                              onChanged: (text) {
                                widget.store.draft(
                                  'answer.${lesson.id}.$i',
                                  text,
                                );
                              },
                            ),
                            TextButton(
                              onPressed: () {
                                SoundScope.of(context)?.cue(SoundCue.hint);
                                setState(
                                  () => answers.contains(i)
                                      ? answers.remove(i)
                                      : answers.add(i),
                                );
                              },
                              child: Text(
                                answers.contains(i)
                                    ? 'Скрыть ориентир'
                                    : 'Как проверить ответ',
                              ),
                            ),
                            if (answers.contains(i))
                              Text(
                                'Найди относящийся к вопросу раздел лекции. Подтверди объяснение небольшим примером и случаем, где первоначальная догадка могла бы ошибиться.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Критерии завершения',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  ...List.generate(
                    lesson.checklist.length,
                    (i) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(lesson.checklist[i]),
                      value: checked.contains(i),
                      onChanged: (value) {
                        SoundScope.of(context)?.cue(SoundCue.toggle);
                        setState(
                          () => value == true
                              ? checked.add(i)
                              : checked.remove(i),
                        );
                        widget.store.draft(
                          'review.${lesson.id}',
                          checked.join(','),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      SoundScope.of(context)?.cue(SoundCue.open);
                      widget.onPractice();
                    },
                    icon: const Icon(Icons.code_rounded),
                    label: Text(
                      lesson.challenge != null
                          ? 'Перейти к заданию с проверкой'
                          : 'Открыть практическую работу',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SelectableText(
                    'Документация: ${widget.course.source}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ConceptDiagram extends StatelessWidget {
  final String kind;
  const ConceptDiagram(this.kind, {super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = switch (kind) {
      'memory' => [
        'Имя → объект',
        'balance → 100',
        'Присваивание',
        'balance → 125',
        'Новое состояние',
      ],
      'branch' => [
        'Проверка условия',
        'Истина → действие A',
        'Ложь → действие B',
        'Продолжение',
      ],
      'loop' => [
        'Начальное состояние',
        'Проверка границы',
        'Обработка элемента',
        'Обновление → проверка',
      ],
      'collection' => [
        'Индекс: 0 | 1 | 2',
        'Данные: 7 | 2 | 9',
        'Длина: 3',
        'Последний индекс: 2',
      ],
      'relation' => [
        'customers: id, name',
        '1 покупатель → N заказов',
        'orders: customer_id',
        'JOIN по ключу',
      ],
      'trace' => [
        'i: 1 → total: 1',
        'i: 2 → total: 3',
        'i: 3 → total: 6',
        'i: 4 → total: 10',
      ],
      'pipeline' => [
        'Данные',
        'Проверка контракта',
        'Преобразование',
        'Результат или ошибка',
      ],
      _ => ['Входные данные', 'Алгоритм', 'Проверяемый результат'],
    };
    return Panel(
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Наглядная схема',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < data.length; i++) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    data[i],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (i < data.length - 1)
                  const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
