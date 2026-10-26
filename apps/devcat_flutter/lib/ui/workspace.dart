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
  int hint = 0, tab = 0;
  bool busy = false;
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
    task = generateChallenge(
      language,
      seed: widget.seed,
      kind: widget.lesson?.kind ?? 'loop',
      lessonId: widget.ide
          ? null
          : widget.seed == 0
          ? widget.lesson?.id
          : null,
    );
    if (language == 'sql' &&
        widget.lesson?.kind == 'filter' &&
        widget.seed == 0) {
      task = generateChallenge(language, seed: 11, lessonId: widget.lesson!.id);
    }
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
    if (!runner.desktop) {
      setState(
        () => output =
            'На Android компилятор этого языка не встроен. Уроки, редактор и генератор работают локально; запускай SQLite или продолжи на ПК через синхронизацию.',
      );
      _showFeedback();
      return false;
    }
    if (widget.store.setting('trustedLocalRun', false)) return true;
    final yes = await confirm(
      context,
      'Запустить локальный код?',
      'Программа выполнится с правами твоего пользователя. Запускай только собственный код: это не изолированная песочница. Компилятор должен быть установлен на компьютере.',
    );
    if (yes) await widget.store.set('trustedLocalRun', true);
    return yes;
  }

  Future<void> _execute(bool check) async {
    if (busy || !await _permission() || !mounted) return;
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
    if (mounted && MediaQuery.sizeOf(context).width < 760) _showFeedback();
  }

  void _showFeedback() {
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
                    decoration: const InputDecoration(labelText: 'stdin'),
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
              IconButton(
                onPressed: busy ? null : _import,
                icon: const Icon(Icons.file_open_outlined),
                tooltip: 'Импортировать файл',
              ),
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
                  fontFamily: widget.store.setting('editorFont', 'monospace'),
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
            if (compact)
              IconButton(
                onPressed: _showFeedback,
                icon: const Icon(Icons.terminal_rounded),
                tooltip: 'Ввод и результат',
              ),
            if (!widget.ide)
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
        if (!compact && language != 'sql')
          SizedBox(
            height: 52,
            child: TextField(
              controller: input,
              decoration: const InputDecoration(
                labelText: 'Стандартный ввод (stdin)',
                isDense: true,
              ),
              maxLines: 1,
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
    return Padding(
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
                'Редактор одного файла. Для запуска на ПК нужны локальные toolchain. На Android встроен SQLite.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: compact || widget.ide
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
  }

  Widget _information(BuildContext context) => ListView(
    children: [
      if (widget.store.setting('cat', true)) ...[
        CatMessage(
          cat,
          reducedMotion: MediaQuery.of(context).disableAnimations,
        ),
        const SizedBox(height: 16),
      ],
      if (widget.seed == 0 && widget.lesson != null) ...[
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
      Text(task.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(task.prompt, style: const TextStyle(height: 1.65)),
      const SizedBox(height: 16),
      if (language == 'sql')
        Panel(
          padding: const EdgeInsets.all(14),
          child: SelectableText(
            sqlFixture,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
      if (task.tests.isNotEmpty)
        Text(
          'Пример: ${task.tests[2].input.trim()} → ${task.tests[2].expected}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      const SizedBox(height: 16),
      TextButton.icon(
        onPressed: () async {
          if (await confirm(
            context,
            'Показать решение?',
            'Эталон откроется в отдельном окне. Попробуй сначала три подсказки.',
          )) {
            if (!context.mounted) return;
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Эталонное решение'),
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
        label: const Text('Посмотреть решение'),
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
          'Источник: ${widget.course!.source}\nРевизия контента: 1 · вводный модуль',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );
}
