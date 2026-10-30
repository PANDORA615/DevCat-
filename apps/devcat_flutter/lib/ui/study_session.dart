import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/course.dart';
import '../core/store.dart';
import '../core/study.dart';
import '../core/study_runner.dart';
import '../core/runner.dart';
import '../core/sound.dart';
import 'cat_actor.dart';
import 'lecture.dart';
import 'study_widgets.dart';
import 'tutor_page.dart';
import 'widgets.dart';

class StudySessionPage extends StatefulWidget {
  final StudyTopic topic;
  final StudyUnit unit;
  final Course course;
  final Lesson lesson;
  final AppStore store;
  final SoftSounds sounds;
  final bool review;
  final VoidCallback onPractice;
  const StudySessionPage({
    super.key,
    required this.topic,
    required this.unit,
    required this.course,
    required this.lesson,
    required this.store,
    required this.sounds,
    required this.onPractice,
    this.review = false,
  });
  @override
  State<StudySessionPage> createState() => _StudySessionPageState();
}

class _StudySessionPageState extends State<StudySessionPage>
    with WidgetsBindingObserver {
  late StudySessionState session;
  late String resumeKey;
  final entry = TextEditingController();
  final scroll = ScrollController();
  final runner = LocalRunner();
  Timer? saveTimer, chatter;
  bool busy = false, awarding = false, completed = false;
  int earned = 0, chatterIndex = 0;
  String? problem;
  String speech = 'Разберём одну небольшую идею. Я рядом!';
  CatMood mood = CatMood.explaining;
  DateTime actionAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    resumeKey =
        'study.resume.v1:${widget.unit.id}${widget.review ? ':review:${studyDay(DateTime.now())}' : ''}';
    final effectiveUnit = widget.review ? widget.unit.forReview() : widget.unit;
    session = StudySessionState(
      effectiveUnit,
      snapshots: StudyLedger.snapshots(widget.store.progress, resumeKey),
    );
    final ledger = StudyLedger(widget.store.progress);
    final recorded = widget.review
        ? ledger.events.any(
            (e) =>
                e['unit'] == widget.unit.id &&
                e['day'] == studyDay(DateTime.now()),
          )
        : ledger.done(widget.unit);
    if (session.complete && widget.review && recorded) {
      session = StudySessionState(
        effectiveUnit,
        generation: session.generation + 1,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_persist());
      });
    }
    completed = session.complete && recorded;
    _loadEntry();
    entry.addListener(_entryChanged);
    if (session.complete && !completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _next();
      });
    }
    final chatterSeconds = widget.store
        .setting<num>('catChatterSeconds', 20)
        .toInt()
        .clamp(10, 120);
    if (widget.store.setting('cat', true) &&
        widget.store.setting('catChatter', true)) {
      chatter = Timer.periodic(Duration(seconds: chatterSeconds), (_) {
        if (!mounted ||
            completed ||
            busy ||
            session.feedback != null ||
            ModalRoute.of(context)?.isCurrent != true ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed ||
            DateTime.now().difference(actionAt).inSeconds < chatterSeconds) {
          return;
        }
        final phrases = [
          'Не спеши. Можно сначала проговорить ответ своими словами.',
          'Если непонятно, нажми «Объяснить». Разберём именно этот шаг.',
          'Ошибка — повод попробовать ещё раз. Мы никуда не торопимся.',
          'Посмотри на один фрагмент кода за раз. Так легче заметить закономерность.',
        ];
        _say(phrases[chatterIndex++ % phrases.length], CatMood.encouragement);
      });
    }
  }

  void _loadEntry() {
    if (session.complete) {
      entry.text = '';
      return;
    }
    final exercise = session.current;
    var text = session.entry;
    if (text.isEmpty && exercise.kind == 'code') {
      text = session.codeEntries[exercise.id] ?? '';
      if (text.isEmpty && exercise.data['mode'] == 'challenge') {
        final drafts = widget.store.progress.draftsFor(
          widget.lesson.challenge!.id,
        );
        text = drafts.isEmpty
            ? widget.lesson.challenge!.starter
            : drafts.first['text'];
      }
    }
    entry.text = text;
    session.entry = text;
  }

  void _entryChanged() {
    session.entry = entry.text;
    actionAt = DateTime.now();
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 450), _persist);
  }

  Future<void> _persist() async {
    try {
      await widget.store.draft(resumeKey, jsonEncode(session.toJson()));
    } catch (e) {
      if (mounted) {
        setState(
          () => problem = 'Не удалось сохранить занятие. Попробуй ещё раз: $e',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      saveTimer?.cancel();
      unawaited(_persist());
    }
  }

  void _say(String text, CatMood nextMood) {
    if (!mounted) return;
    setState(() {
      speech = text;
      mood = nextMood;
    });
    if (widget.store.setting('cat', true)) widget.sounds.speak(nextMood);
  }

  Future<void> _check() async {
    if (busy || session.complete || session.feedback != null) return;
    final exercise = session.current;
    actionAt = DateTime.now();
    FocusManager.instance.primaryFocus?.unfocus();
    if (exercise.kind == 'code') {
      if (widget.course.id != 'sql' &&
          !widget.store.setting('trustedLocalRun', false)) {
        final yes = await confirm(
          context,
          'Запустить локальный код?',
          'Программа выполнится с правами приложения. На Android все среды уже входят в APK; на компьютере нужен установленный локальный компилятор. Запускай только собственный код.',
        );
        if (!yes || !mounted) return;
        await widget.store.set('trustedLocalRun', true);
      }
      if (!mounted) return;
      setState(() {
        busy = true;
        problem = null;
      });
      try {
        final key = exercise.data['mode'] == 'challenge'
            ? widget.lesson.challenge!.id
            : 'study.code.${widget.lesson.id}';
        await widget.store.draft(key, studySource(exercise, entry.text));
        final result = await evaluateStudyCode(
          runner,
          widget.course,
          widget.lesson,
          exercise,
          entry.text,
        );
        if (!mounted) return;
        if (!result.evaluated) {
          setState(() => problem = 'Проверка не завершена. ${result.report}');
          return;
        }
        if (exercise.data['mode'] == 'challenge') {
          await widget.store.record(
            widget.lesson.challenge!.id,
            widget.course.id,
            result.passed,
          );
        }
        session.checked(result.passed, explanation: result.report);
      } catch (e) {
        if (mounted) {
          setState(() => problem = 'Не удалось выполнить проверку: $e');
        }
        return;
      } finally {
        if (mounted) setState(() => busy = false);
      }
    } else {
      final response = switch (exercise.kind) {
        'choice' => session.selectedOption ?? '',
        'order' => session.selectedPieces.map((i) => exercise.pieces[i]).join(),
        _ => entry.text,
      };
      session.checked(exercise.accepts(response));
    }
    if (!mounted || session.feedback == null) return;
    final correct = session.feedback!;
    await widget.sounds.result(correct);
    if (!mounted) return;
    _say(
      correct
          ? 'Да, получилось! Пойдём дальше.'
          : 'Почти. Разберём этот шаг и попробуем его ещё раз.',
      correct ? CatMood.celebration : CatMood.encouragement,
    );
    setState(() {});
    await _persist();
  }

  Future<void> _next() async {
    if (busy || awarding) return;
    saveTimer?.cancel();
    session.advance();
    entry.removeListener(_entryChanged);
    _loadEntry();
    entry.addListener(_entryChanged);
    problem = null;
    actionAt = DateTime.now();
    if (session.complete) {
      setState(() => awarding = true);
      final before = StudyLedger(widget.store.progress).xp;
      final now = DateTime.now();
      try {
        await widget.store.studyRecords({
          resumeKey: jsonEncode(session.toJson()),
          StudyLedger.eventKey(widget.unit, now): StudyLedger.event(
            widget.unit,
            session.wrong,
            now,
          ),
        });
        if (!mounted) return;
        earned = StudyLedger(widget.store.progress).xp - before;
        completed = true;
        _say(
          'Занятие закончено! Ты сделал ещё один настоящий шаг.',
          CatMood.celebration,
        );
        widget.sounds.cue(SoundCue.success);
      } catch (e) {
        if (mounted) {
          setState(() => problem = 'Не получилось сохранить результат: $e');
        }
      } finally {
        if (mounted) setState(() => awarding = false);
      }
    } else {
      _say(
        session.current.informational
            ? 'Небольшое объяснение — и сразу попробуем.'
            : 'Теперь твоя очередь. Если что, я помогу.',
        CatMood.explaining,
      );
      await _persist();
      if (scroll.hasClients) scroll.jumpTo(0);
    }
    if (mounted) setState(() {});
  }

  void _explain() {
    if (completed || session.complete) return;
    widget.sounds.cue(SoundCue.hint);
    final exercise = session.current;
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
                'Давай разберём',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                exercise.why.isEmpty ? exercise.text : exercise.why,
                style: const TextStyle(fontSize: 18, height: 1.6),
              ),
              if (exercise.kind == 'fill' || exercise.kind == 'write')
                StudyCode('Фрагмент: ${exercise.answer}'),
              if (exercise.kind == 'order') StudyCode(exercise.pieces.join()),
              if (exercise.kind == 'code' &&
                  widget.lesson.challenge != null) ...[
                const SizedBox(height: 12),
                Text(widget.lesson.challenge!.hints.first),
              ],
              const SizedBox(height: 20),
              StudyButton(
                label: 'ПОНЯТНО, ПОПРОБУЮ',
                onPressed: () => Navigator.pop(sheet),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  _theory();
                },
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Подробная теория с примерами'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  _tutor();
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Задать вопрос коту'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _theory() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (page) => Scaffold(
        appBar: AppBar(title: const Text('Подробное объяснение')),
        body: LectureView(
          lesson: widget.lesson,
          course: widget.course,
          store: widget.store,
          onPractice: () {
            Navigator.pop(page);
            widget.onPractice();
          },
        ),
      ),
    ),
  );

  void _tutor() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TutorPage(
        store: widget.store,
        courses: [widget.course],
        lessonId: widget.lesson.id,
      ),
    ),
  );

  bool get ready {
    if (session.complete) return false;
    final e = session.current;
    return switch (e.kind) {
      'learn' => true,
      'choice' => session.selectedOption != null,
      'order' => session.selectedPieces.length == e.pieces.length,
      _ => entry.text.trim().isNotEmpty,
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    saveTimer?.cancel();
    chatter?.cancel();
    runner.cancel();
    widget.store
        .draft(resumeKey, jsonEncode(session.toJson()))
        .catchError((_) {});
    entry.removeListener(_entryChanged);
    entry.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'К маршруту',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: completed ? 1 : session.fraction),
                      duration: Duration(
                        milliseconds: MediaQuery.of(context).disableAnimations
                            ? 0
                            : 350,
                      ),
                      builder: (_, value, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 13,
                          backgroundColor: scheme.surfaceContainerHighest,
                          semanticsLabel: 'Прогресс занятия',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  StudyMetric(
                    completed
                        ? Icons.bolt_rounded
                        : Icons.check_circle_outline_rounded,
                    completed
                        ? '+$earned'
                        : '${session.answered}/${session.questionCount}',
                    completed ? 'опыта XP' : 'верных ответов',
                  ),
                ],
              ),
            ),
            Expanded(
              child: completed
                  ? _celebration()
                  : session.complete
                  ? _saving()
                  : _exercise(),
            ),
            if (!completed && !session.complete)
              AnimatedSize(
                duration: Duration(
                  milliseconds: MediaQuery.of(context).disableAnimations
                      ? 0
                      : 200,
                ),
                alignment: Alignment.bottomCenter,
                curve: Curves.easeOutCubic,
                child: _bottom(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cardTransition(Widget child) => AnimatedSwitcher(
    duration: Duration(
      milliseconds: MediaQuery.of(context).disableAnimations ? 0 : 220,
    ),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      children: [
        ...previous.map(
          (old) => IgnorePointer(child: ExcludeSemantics(child: old)),
        ),
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .025),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: child,
  );

  Widget _exercise() {
    final exercise = session.current;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: _cardTransition(
            Column(
              key: ValueKey(exercise.id),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.course.name} · ${widget.unit.title}${widget.review ? ' · Повторение' : ''}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (widget.store.setting('cat', true))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        CatActor(size: 76, mood: mood, speech: speech),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: scheme.outlineVariant,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              speech,
                              style: const TextStyle(fontSize: 14, height: 1.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  exercise.prompt,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 18),
                if (exercise.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      exercise.text,
                      style: const TextStyle(fontSize: 19, height: 1.65),
                    ),
                  ),
                if (exercise.data['image'] is String)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: InkWell(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (dialog) => Dialog.fullscreen(
                          child: SafeArea(
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    onPressed: () => Navigator.pop(dialog),
                                    icon: const Icon(Icons.close_rounded),
                                    tooltip: 'Закрыть иллюстрацию',
                                  ),
                                ),
                                Expanded(
                                  child: InteractiveViewer(
                                    maxScale: 5,
                                    child: Image.asset(
                                      'assets/content/${exercise.data['image']}',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              'assets/content/${exercise.data['image']}',
                              height: 200,
                              fit: BoxFit.contain,
                              semanticLabel: exercise.data['imageCaption'],
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Нажми, чтобы рассмотреть',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (exercise.kind == 'code')
                  ..._codeExercise(exercise)
                else if (exercise.kind == 'order')
                  ..._ordering(exercise)
                else ...[
                  if (exercise.code.isNotEmpty) _program(exercise.code),
                  if (exercise.data.containsKey('input')) ...[
                    const Text(
                      'Данные для программы',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    StudyCode(
                      (exercise.data['input'] as String).isEmpty
                          ? 'Ввод не требуется'
                          : exercise.data['input'],
                    ),
                  ],
                  if (exercise.kind == 'choice')
                    ...exercise.options.asMap().entries.map(
                      (option) => StudyOption(
                        key: ValueKey('${exercise.id}:option:${option.key}'),
                        text: option.value,
                        number: option.key + 1,
                        selected: session.selectedOption == option.value,
                        enabled: session.feedback == null,
                        onTap: () {
                          setState(() => session.selectedOption = option.value);
                          unawaited(_persist());
                        },
                      ),
                    ),
                  if (exercise.kind == 'fill' || exercise.kind == 'write')
                    _answerField(exercise),
                ],
                if (problem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text(
                      problem!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: busy ? null : _explain,
                    icon: const Icon(Icons.lightbulb_outline_rounded),
                    label: const Text('Объяснить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _program(String code) => code.split('\n').length <= 14
      ? StudyCode(code)
      : ExpansionTile(
          title: const Text('Посмотреть всю программу'),
          subtitle: Text(
            '${code.split('\n').length} строк · можно раскрыть перед ответом',
          ),
          children: [StudyCode(code)],
        );

  Widget _answerField(StudyExercise exercise, {bool multiline = false}) =>
      TextField(
        key: ValueKey('study-answer:${exercise.id}'),
        controller: entry,
        readOnly: busy || session.feedback != null,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        minLines: multiline ? 7 : 1,
        maxLines: multiline ? 16 : 3,
        textInputAction: multiline
            ? TextInputAction.newline
            : TextInputAction.done,
        onSubmitted: multiline
            ? null
            : (_) {
                if (ready && session.feedback == null) _check();
              },
        style: TextStyle(
          fontFamily: multiline || exercise.kind != 'write'
              ? 'JetBrainsMono'
              : 'Nunito',
          fontSize: 17,
          height: 1.6,
        ),
        decoration: InputDecoration(
          labelText: multiline ? 'Твоё решение' : 'Твой ответ',
          hintText: multiline ? null : 'Введи ответ',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(width: 2),
          ),
        ),
        onChanged: (_) => setState(() {}),
      );

  List<Widget> _codeExercise(StudyExercise exercise) {
    final challenge = widget.lesson.challenge;
    if (exercise.data['mode'] == 'challenge') {
      return [
        Text(
          challenge!.prompt,
          style: const TextStyle(fontSize: 17, height: 1.6),
        ),
        if ((widget.lesson.learning['practiceExplanation'] as String? ?? '')
            .isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(widget.lesson.learning['practiceExplanation']),
          ),
        if (challenge.tests.isNotEmpty)
          ExpansionTile(
            title: const Text('Пример входа и результата'),
            children: [
              StudyCode(
                'Вход:\n${challenge.tests.first.input}\nОжидается:\n${challenge.tests.first.expected}',
              ),
            ],
          ),
        const SizedBox(height: 14),
        _answerField(exercise, multiline: true),
      ];
    }
    final cases = widget.lesson.runnableExample!['tests'] as List;
    final sample = cases.first as Map;
    return [
      _program(exercise.code),
      const Text(
        'Замени только ___ своим фрагментом. Затем программа действительно запустится на устройстве.',
        style: TextStyle(fontSize: 17, height: 1.6),
      ),
      const SizedBox(height: 16),
      _answerField(exercise),
      ExpansionTile(
        title: const Text('Данные и цель запуска'),
        children: [
          StudyCode(
            'Вход:\n${(sample['input'] as String).isEmpty ? 'Ввод не требуется' : sample['input']}\nОжидается:\n${sample['expected']}',
          ),
        ],
      ),
    ];
  }

  List<Widget> _ordering(StudyExercise exercise) {
    final indices = List<int>.generate(exercise.pieces.length, (i) => i)
      ..shuffle(Random(exercise.id.hashCode));
    if (indices.asMap().entries.every((e) => e.key == e.value)) {
      indices.add(indices.removeAt(0));
    }
    return [
      Container(
        constraints: const BoxConstraints(minHeight: 95),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
        ),
        child: session.selectedPieces.isEmpty
            ? const Center(child: Text('Нажимай на блоки в нужном порядке'))
            : Wrap(
                spacing: 7,
                runSpacing: 9,
                children: [
                  for (final index in session.selectedPieces)
                    InputChip(
                      label: Text(
                        exercise.pieces[index].trim(),
                        style: const TextStyle(fontFamily: 'JetBrainsMono'),
                      ),
                      onDeleted: session.feedback == null
                          ? () => setState(
                              () => session.selectedPieces.remove(index),
                            )
                          : null,
                    ),
                ],
              ),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 10,
        children: [
          for (final index in indices)
            ActionChip(
              key: ValueKey('${exercise.id}:piece:$index'),
              label: Text(
                exercise.pieces[index].trim(),
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 16,
                ),
              ),
              onPressed:
                  session.feedback != null ||
                      session.selectedPieces.contains(index)
                  ? null
                  : () {
                      setState(() => session.selectedPieces.add(index));
                      unawaited(_persist());
                    },
            ),
        ],
      ),
      TextButton(
        onPressed: session.feedback != null
            ? null
            : () => setState(() => session.selectedPieces.clear()),
        child: const Text('Начать сборку заново'),
      ),
    ];
  }

  Widget _bottom() {
    final exercise = session.current;
    final feedback = session.feedback;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: feedback == true
            ? scheme.primaryContainer
            : feedback == false
            ? scheme.tertiaryContainer
            : scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant, width: 2)),
      ),
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (feedback != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: max(
                        60,
                        MediaQuery.sizeOf(context).height * .25,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                feedback
                                    ? Icons.check_circle_rounded
                                    : Icons.lightbulb_rounded,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  feedback
                                      ? 'Верно!'
                                      : 'Разберём и попробуем ещё раз',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 19,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            exercise.why,
                            style: const TextStyle(fontSize: 16, height: 1.5),
                          ),
                          if (!feedback && exercise.kind == 'order')
                            StudyCode(exercise.pieces.join()),
                          if (!feedback &&
                              (exercise.kind == 'fill' ||
                                  exercise.kind == 'write' ||
                                  exercise.kind == 'choice'))
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Правильный ответ: ${exercise.answer}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          if (session.detail.isNotEmpty)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                feedback
                                    ? 'Результат запуска'
                                    : 'Что показала проверка',
                              ),
                              children: [SelectableText(session.detail)],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (feedback != null) const SizedBox(height: 14),
                if (busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text(
                    'Запускаю код локально… Первый запуск среды может занять время.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: runner.cancel,
                    child: const Text('Остановить проверку'),
                  ),
                ] else
                  StudyButton(
                    label: feedback != null || exercise.informational
                        ? 'ПРОДОЛЖИТЬ'
                        : 'ПРОВЕРИТЬ',
                    onPressed: awarding || !(ready || feedback != null)
                        ? null
                        : feedback != null || exercise.informational
                        ? _next
                        : _check,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _saving() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (awarding) const CircularProgressIndicator(),
          Text(problem ?? 'Сохраняю результат…', textAlign: TextAlign.center),
          if (!awarding && problem != null)
            StudyButton(label: 'СОХРАНИТЬ ЕЩЁ РАЗ', onPressed: _next),
        ],
      ),
    ),
  );

  Widget _celebration() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          children: [
            CatActor(size: 180, mood: CatMood.celebration, speech: speech),
            const SizedBox(height: 20),
            Text(
              'Ещё один шаг сделан!',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              widget.lesson.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 12,
              children: [
                StudyMetric(Icons.bolt_rounded, '+$earned XP', 'опыт'),
                StudyMetric(
                  Icons.check_circle_outline_rounded,
                  '${session.questionCount - session.wrong.length}/${session.questionCount}',
                  'с первой попытки',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              session.wrong.isEmpty
                  ? 'Все вопросы разобраны. Прогресс сохранён.'
                  : 'Ошибки вернулись на повторение, и ты справился с ними. Прогресс сохранён.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: StudyButton(
                label: 'К МАРШРУТУ',
                icon: Icons.route_rounded,
                onPressed: () => Navigator.pop(context, true),
              ),
            ),
            TextButton.icon(
              onPressed: widget.onPractice,
              icon: const Icon(Icons.code_rounded),
              label: const Text('Закрепить в IDE'),
            ),
          ],
        ),
      ),
    ),
  );
}
