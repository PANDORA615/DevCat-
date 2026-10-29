import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/sql.dart';
import '../core/course.dart';
import '../core/runner.dart';
import '../core/store.dart';
import '../core/sound.dart';
import 'widgets.dart';
import 'transfer.dart';

class WorkspacePage extends StatefulWidget {
  final AppStore store;
  final String language;
  final SoftSounds sounds;
  final Course? course;
  final Lesson? lesson;
  final int seed;
  final bool ide;
  const WorkspacePage({
    super.key,
    required this.store,
    required this.language,
    required this.sounds,
    this.course,
    this.lesson,
    this.seed = 0,
    this.ide = false,
  });
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  final runner = LocalRunner();
  late CodeController code;
  late Challenge task;
  late String language;
  final input = TextEditingController(text: '10\n');
  Timer? debounce;
  String
  output = 'Результат появится здесь. Код не отправляется на сервер.',
  cat =
      'Попробуй самостоятельно. Если застрянешь — начнём с маленькой подсказки.';
  int hint = 0, tab = 1, compactPane = 0;
  bool busy = false;
  CatMood mood = CatMood.encouragement;
  bool get manual => widget.seed == 0 && widget.lesson?.kind == 'review';
  String? failure;
  String get taskKey => widget.ide ? 'ide.$language' : task.id;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    language = widget.language;
    _configure();
  }

  void _configure() {
    task = widget.seed == 0 && widget.lesson?.challenge != null
        ? widget.lesson!.challenge!
        : generateChallenge(
            language,
            seed: widget.seed,
            kind: widget.lesson?.kind ?? 'loop',
            lessonId: widget.ide
                ? null
                : widget.seed == 0
                ? widget.lesson?.id
                : null,
          );
    if (manual) {
      task = Challenge(
        id: widget.lesson!.id,
        language: language,
        title: widget.lesson!.title,
        prompt: widget.lesson!.assignment,
        starter: widget.lesson!.examples.isNotEmpty
            ? widget.lesson!.examples.first
            : generateChallenge(language).starter,
        solution: widget.lesson!.examples.join('\n'),
        hints: widget.lesson!.questions.take(3).toList(),
        tests: const [],
      );
    }
    final cases = sampleCases;
    input.text = cases.isEmpty ? '' : cases.first.input;
    final draft = widget.store.progress.draftsFor(taskKey);
    code = CodeController(
      text: draft.isNotEmpty ? draft.first['text'] : task.starter,
      language: switch (language) {
        'c' || 'cpp' => cpp,
        'csharp' => cs,
        'python' => python,
        'java' => java,
        'javascript' => javascript,
        'go' => go,
        _ => sql,
      },
    );
    code.addListener(_changed);
  }

  List<Case> get sampleCases {
    if (task.tests.isNotEmpty) return task.tests;
    final examples = widget.lesson?.runnableExample?['tests'] as List?;
    return [
      for (final item in examples ?? [])
        Case(item['input'] as String, item['expected'] as String),
    ];
  }

  void _changed() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 450), _save);
  }

  Future<void> _save() async {
    try {
      await widget.store.draft(taskKey, code.fullText);
    } catch (e) {
      if (mounted) setState(() => failure = 'Черновик не сохранён: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      debounce?.cancel();
      _save();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debounce?.cancel();
    widget.store.draft(taskKey, code.fullText).catchError((_) {});
    runner.cancel();
    code.removeListener(_changed);
    code.dispose();
    input.dispose();
    super.dispose();
  }

  Future<bool> _permission() async {
    if (language == 'sql') return true;
    if (!runner.supported) {
      setState(
        () => output = 'Исполнение кода на этой платформе не поддерживается.',
      );
      _showFeedback();
      return false;
    }
    if (widget.store.setting('trustedLocalRun', false)) return true;
    final yes = await confirm(
      context,
      'Запустить локальный код?',
      'Программа выполнится локально с правами приложения. Запускай только собственный код: это не изолированная песочница. На Android компиляторы входят в APK; при первом запуске потребуется время и свободное место для их подготовки. На компьютере нужен установленный компилятор.',
    );
    if (yes) await widget.store.set('trustedLocalRun', true);
    return yes;
  }

  Future<void> _execute(bool check) async {
    if (busy || !await _permission() || !mounted) return;
    widget.sounds.cue(SoundCue.open);
    await _save();
    if (!mounted) return;
    final source = code.fullText;
    setState(() {
      busy = true;
      output = check ? 'Проверяю на настоящих тестах…' : 'Выполняю локально…';
      failure = null;
    });
    try {
      if (check) {
        final result = await runner.check(task, source);
        if (result.evaluated) {
          await widget.store.record(task.id, language, result.passed);
        }
        await widget.sounds.result(result.passed);
        if (mounted) {
          setState(() {
            output = result.report;
            mood = result.passed ? CatMood.celebration : CatMood.warning;
            cat = result.passed
                ? 'Получилось! Все проверки пройдены. Сможешь объяснить, почему решение работает на границе диапазона?'
                : explainDiagnostic(result.report);
          });
        }
      } else {
        final result = await runner.run(language, source, input.text);
        if (mounted) {
          setState(() {
            output =
                '${result.output}${result.error.isNotEmpty ? '\n${result.error}' : ''}\n\nКод завершения: ${result.exitCode}';
            mood = result.ok ? CatMood.encouragement : CatMood.warning;
            widget.sounds.cue(result.ok ? SoundCue.save : SoundCue.error);
            cat = result.ok
                ? 'Программа выполнилась. Теперь проверь, совпадает ли результат с условием.'
                : explainDiagnostic(result.error);
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => output = 'Не удалось выполнить проверку: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && MediaQuery.sizeOf(context).width < 760) {
      setState(() => compactPane = 2);
    }
  }

  void _showFeedback() {
    if (MediaQuery.sizeOf(context).width < 760) {
      setState(() => compactPane = 2);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .55,
            child: ListView(
              children: [
                Text(
                  'Ввод и результат',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (language != 'sql')
                  TextField(
                    controller: input,
                    decoration: const InputDecoration(
                      labelText: 'Данные для программы',
                    ),
                    maxLines: 2,
                  ),
                const SizedBox(height: 16),
                SelectableText(
                  output,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text(cat),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _import() async {
    try {
      final file = await openFile();
      if (file == null) return;
      if (await file.length() > 200000) {
        throw const FormatException('Для редактора 0.1 лимит файла — 200 КБ.');
      }
      final text = await file.readAsString();
      if (!mounted) return;
      if (!await confirm(
        context,
        'Открыть файл?',
        'Текущий черновик будет заменён содержимым ${file.name}. Исходный файл на диске не изменится.',
      )) {
        return;
      }
      if (mounted) {
        code.text = text;
        await _save();
      }
    } catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 760;
    final drafts = widget.store.progress.draftsFor(taskKey);
    final info = _information(context);
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(Icons.description_outlined, fileNames[language]!),
              if (widget.ide)
                DropdownButton<String>(
                  value: language,
                  items: languageNames.entries
                      .where((e) => e.key != 'html' && e.key != 'css')
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (value) async {
                          if (value == null) return;
                          await _save();
                          code.removeListener(_changed);
                          code.dispose();
                          setState(() {
                            language = value;
                            _configure();
                            output = 'Выбран ${languageNames[language]}.';
                          });
                        },
                ),
              const Text(
                'Автосохранение · локально',
                style: TextStyle(fontSize: 11),
              ),
              if (!compact || widget.ide)
                IconButton(
                  onPressed: busy ? null : _import,
                  icon: const Icon(Icons.file_open_outlined),
                  tooltip: 'Импортировать файл',
                ),
              if (!compact || widget.ide)
                IconButton(
                  onPressed: () async {
                    try {
                      await exportText(
                        context,
                        widget.store.directory,
                        fileNames[language]!,
                        code.fullText,
                      );
                    } catch (e) {
                      if (mounted) setState(() => failure = '$e');
                    }
                  },
                  icon: const Icon(Icons.save_alt_rounded),
                  tooltip: 'Экспортировать код',
                ),
              if (drafts.length > 1)
                PopupMenuButton<Map<String, dynamic>>(
                  tooltip: 'Черновики с устройств',
                  icon: const Icon(Icons.devices_rounded),
                  itemBuilder: (_) => drafts
                      .map(
                        (d) => PopupMenuItem(
                          value: d,
                          child: Text(
                            'Устройство ${(d['device'] as String).substring(0, 6)} · ${DateTime.fromMillisecondsSinceEpoch(d['updated'])}',
                          ),
                        ),
                      )
                      .toList(),
                  onSelected: (d) {
                    code.text = d['text'];
                  },
                ),
            ],
          ),
        ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(failure!, style: TextStyle(color: scheme.error)),
          ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: CodeTheme(
              data: CodeThemeData(
                styles: {
                  'root': TextStyle(
                    color: scheme.onSurface,
                    backgroundColor: scheme.surfaceContainerLowest,
                  ),
                  'keyword': TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  'string': TextStyle(color: scheme.tertiary),
                  'number': TextStyle(color: scheme.secondary),
                  'comment': TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  'built_in': TextStyle(color: scheme.primary),
                },
              ),
              child: CodeField(
                controller: code,
                expands: true,
                maxLines: null,
                minLines: null,
                background: scheme.surfaceContainerLowest,
                gutterStyle: GutterStyle(
                  width: 48,
                  showErrors: false,
                  showFoldingHandles: true,
                  background: scheme.surfaceContainerLow,
                ),
                padding: const EdgeInsets.all(12),
                textStyle: TextStyle(
                  fontFamily: widget.store.setting(
                    'editorFont',
                    'JetBrainsMono',
                  ),
                  fontWeight: FontWeight.w500,
                  fontSize: widget.store
                      .setting<num>('editorSize', 14)
                      .toDouble(),
                  height: 1.55,
                ),
                readOnly: busy,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => _execute(false),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Запустить'),
            ),
            if (compact && widget.ide)
              IconButton(
                onPressed: _showFeedback,
                icon: const Icon(Icons.terminal_rounded),
                tooltip: 'Ввод и результат',
              ),
            if (!widget.ide && !manual)
              FilledButton.tonalIcon(
                onPressed: busy ? null : () => _execute(true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Проверить'),
              ),
            if (busy)
              OutlinedButton.icon(
                onPressed: runner.cancel,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Стоп'),
              ),
            if (!widget.ide)
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        setState(() {
                          widget.sounds.cue(SoundCue.hint);
                          mood = CatMood.thinking;
                          cat = task.hints[hint.clamp(0, 2)];
                          hint = (hint + 1).clamp(0, 3);
                        });
                        if (compact || !widget.store.setting('cat', true)) {
                          _showFeedback();
                        }
                      },
                icon: const Icon(Icons.lightbulb_outline_rounded),
                label: Text('Подсказка ${hint.clamp(0, 2) + 1}/3'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (language != 'sql')
          SizedBox(
            height: compact ? 80 : 52,
            child: TextField(
              controller: input,
              decoration: const InputDecoration(
                labelText: 'Данные для программы (вход)',
                isDense: true,
              ),
              maxLines: compact ? 2 : 1,
            ),
          ),
        const SizedBox(height: 8),
        if (!compact)
          SizedBox(
            height: compact ? 150 : 165,
            child: Panel(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: SelectableText(
                  output,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: scheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    final layout = Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 8, compact ? 16 : 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.ide
                        ? 'Мастерская · локальный файл'
                        : widget.seed > 0
                        ? 'Задание от кота · #${widget.seed}'
                        : widget.lesson?.title ?? task.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.store.progress.solved.contains(task.id) &&
                    !widget.ide)
                  const Icon(Icons.task_alt_rounded),
                if (compact && !widget.ide)
                  IconButton(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (context) => SizedBox(
                        height: MediaQuery.sizeOf(context).height * .8,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: info,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.auto_stories_outlined),
                    tooltip: 'Условие и теория',
                  ),
              ],
            ),
          ),
          if (widget.ide)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Редактор одного файла. На Android среды исполнения входят в APK и работают без интернета. На ПК используются установленные компиляторы.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          if (compact && !widget.ide) ...[
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Условие')),
                ButtonSegment(value: 1, label: Text('Редактор')),
                ButtonSegment(value: 2, label: Text('Результат')),
              ],
              selected: {compactPane},
              onSelectionChanged: (v) => setState(() => compactPane = v.first),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: compact && !widget.ide && compactPane == 0
                ? info
                : compact && !widget.ide && compactPane == 2
                ? _results(context)
                : compact || widget.ide
                ? editor
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 310, child: info),
                      const SizedBox(width: 20),
                      Expanded(child: editor),
                    ],
                  ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        final minimum = compact ? 650.0 : 600.0;
        if (bounds.maxHeight < minimum) {
          return SingleChildScrollView(
            child: SizedBox(height: minimum, child: layout),
          );
        }
        return layout;
      },
    );
  }

  Widget _results(BuildContext context) => ListView(
    children: [
      Text('Результат запуска', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      SelectableText(
        output,
        style: const TextStyle(fontFamily: 'JetBrainsMono', height: 1.6),
      ),
      const SizedBox(height: 16),
      Text(cat, style: const TextStyle(height: 1.6)),
      const SizedBox(height: 16),
      FilledButton.tonalIcon(
        onPressed: () => setState(() => compactPane = 1),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Вернуться к коду'),
      ),
    ],
  );

  Widget _information(BuildContext context) => ListView(
    children: [
      if (widget.store.setting('cat', true) &&
          widget.lesson?.learning.isNotEmpty != true) ...[
        CatMessage(
          cat,
          reducedMotion: MediaQuery.of(context).disableAnimations,
          mood: mood,
        ),
        const SizedBox(height: 16),
      ],
      if (widget.seed == 0 &&
          widget.lesson != null &&
          widget.lesson!.learning.isEmpty) ...[
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Теория')),
            ButtonSegment(value: 1, label: Text('Практика')),
          ],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
        const SizedBox(height: 20),
      ],
      if (tab == 0 && widget.seed == 0 && widget.lesson != null) ...[
        Text(widget.lesson!.theory, style: const TextStyle(height: 1.65)),
        const SizedBox(height: 18),
        ...widget.lesson!.examples.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                e,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('Частые ошибки', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        ...widget.lesson!.mistakes.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '• $m',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ),
        const Divider(height: 30),
      ],
      if (manual)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            widget.lesson?.learning['assessment'] == 'experiment'
                ? 'Это опыт: запусти готовый пример и сравни результат. Кнопка автопроверки здесь не требуется.'
                : 'Самостоятельный проект: проверь результат по критериям урока. Автоматическая оценка здесь не выполняется.',
          ),
        ),
      Text(task.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(task.prompt, style: const TextStyle(height: 1.65)),
      if (widget.lesson?.learning['practiceExplanation']
          case final String explanation) ...[
        const SizedBox(height: 14),
        Text(
          'Как понять условие',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(explanation, style: const TextStyle(height: 1.65)),
      ],
      if (widget.lesson?.learning['practicePreview']
          case final Map preview) ...[
        const SizedBox(height: 14),
        Text(
          'Ожидаемый результат на учебной базе',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (final column in preview['columns'] as List)
                DataColumn(label: Text(column as String)),
            ],
            rows: [
              for (final row in preview['rows'] as List)
                DataRow(
                  cells: [
                    for (final value in row as List)
                      DataCell(Text(value as String)),
                  ],
                ),
            ],
          ),
        ),
        const Text(
          'Автопроверка использует ещё один набор данных. Запрос должен получить ответ из таблиц, а не напечатать эти значения как константы.',
        ),
      ],
      const SizedBox(height: 16),
      if (language == 'sql' && widget.lesson?.id.contains('.zero.') != true)
        ExpansionTile(
          title: const Text('Таблицы учебной базы'),
          subtitle: const Text(
            'Открой, чтобы проверить исходные данные запроса',
          ),
          children: [
            SelectableText(
              sqlFixture,
              style: const TextStyle(fontSize: 12, fontFamily: 'JetBrainsMono'),
            ),
          ],
        ),
      for (final example in sampleCases.take(2)) ...[
        Text('Пример запуска', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Panel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Данные для программы'),
              SelectableText(
                example.input.isEmpty ? 'Ввод не требуется' : example.input,
                style: const TextStyle(fontFamily: 'JetBrainsMono'),
              ),
              const SizedBox(height: 10),
              const Text('Ожидаемый результат'),
              SelectableText(
                example.expected,
                style: const TextStyle(fontFamily: 'JetBrainsMono'),
              ),
            ],
          ),
        ),
        if (language != 'sql')
          TextButton(
            onPressed: () => setState(() {
              input.text = example.input;
              compactPane = 1;
            }),
            child: const Text('Подставить этот вход и открыть код'),
          ),
        const SizedBox(height: 12),
      ],
      if (MediaQuery.sizeOf(context).width < 760 && !widget.ide)
        FilledButton.icon(
          onPressed: () => setState(() => compactPane = 1),
          icon: const Icon(Icons.code_rounded),
          label: const Text('Условие понятно — открыть код'),
        ),
      const SizedBox(height: 12),
      if (task.tests.isNotEmpty)
        Text(
          'Пример: ${task.tests.first.input.trim()} → ${task.tests.first.expected}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      const SizedBox(height: 16),
      TextButton.icon(
        onPressed: () async {
          if (await confirm(
            context,
            manual ? 'Открыть пример?' : 'Показать решение?',
            manual
                ? 'Это учебный фрагмент для разбора, а не полная реализация проекта.'
                : 'Эталон откроется в отдельном окне. Попробуй сначала три подсказки.',
          )) {
            if (!context.mounted) return;
            widget.sounds.speak(CatMood.explaining);
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(manual ? 'Пример из лекции' : 'Эталонное решение'),
                content: SingleChildScrollView(
                  child: SelectableText(
                    task.solution,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
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
        },
        icon: const Icon(Icons.visibility_outlined),
        label: Text(manual ? 'Пример из лекции' : 'Посмотреть решение'),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () async {
                if (await confirm(
                  context,
                  'Сбросить редактор?',
                  'Текущий черновик заменится начальным кодом задания.',
                )) {
                  code.text = task.starter;
                  await _save();
                }
              },
        child: const Text('Начать заново'),
      ),
      if (widget.course != null)
        SelectableText(
          'Дополнительное чтение: ${widget.course!.source}\n${manual ? 'Сравни результат с критерием урока.' : 'Кнопка «Проверить» запустит решение на нескольких входах.'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );
}
