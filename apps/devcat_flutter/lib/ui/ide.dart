import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/sql.dart';
import '../core/course.dart';
import '../core/project.dart';
import '../core/store.dart';
import '../core/sound.dart';
import '../core/runner.dart';
import 'widgets.dart';
import '../core/web_preview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/css.dart';
import 'transfer.dart';

class IdePage extends StatefulWidget {
  final AppStore store;
  final SoftSounds sounds;
  final String language;
  const IdePage({
    super.key,
    required this.store,
    required this.sounds,
    required this.language,
  });
  @override
  State<IdePage> createState() => _IdePageState();
}

class _IdePageState extends State<IdePage> with WidgetsBindingObserver {
  final runner = LocalRunner();
  final preview = WebPreview();
  late DevProject project;
  late CodeController code;
  String active = '', output = 'Вывод программы появится здесь.', filter = '';
  final List<String> tabs = [];
  final stdin = TextEditingController(),
      search = TextEditingController(),
      replacement = TextEditingController();
  Timer? debounce;
  bool busy = false, find = false;
  String? warning;
  List<Map<String, dynamic>> get versions =>
      widget.store.progress.drafts.values
          .where((d) => (d['task'] as String).startsWith('project.'))
          .toList()
        ..sort((a, b) => (b['updated'] as int).compareTo(a['updated'] as int));
  List<DevProject> get projects {
    final seen = <String>{};
    final result = <DevProject>[];
    for (final version in versions) {
      try {
        final p = DevProject.decode(version['text']);
        if (seen.add(p.id)) result.add(p);
      } catch (_) {
        /* Malformed imports never replace a project. */
      }
    }
    return result;
  }

  List<Map<String, dynamic>> get legacyDrafts =>
      widget.store.progress.drafts.values
          .where(
            (d) =>
                (d['task'] as String).startsWith('ide.') &&
                languageNames.containsKey((d['task'] as String).substring(4)),
          )
          .toList()
        ..sort((a, b) => (b['updated'] as int).compareTo(a['updated'] as int));
  DevProject _fromLegacy(Map<String, dynamic> draft) {
    final lang = (draft['task'] as String).substring(4);
    final result = DevProject.create(
      lang,
      'Мастерская 0.1 · ${languageNames[lang]}',
    );
    result.files[result.entry] = draft['text'];
    return result;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final saved = projects;
    project = widget.language == 'html' || widget.language == 'css'
        ? saved.where((p) => p.language == widget.language).firstOrNull ??
              DevProject.create(widget.language, 'Мой первый сайт')
        : saved.isEmpty
        ? (legacyDrafts.isNotEmpty
              ? _fromLegacy(legacyDrafts.first)
              : DevProject.create(widget.language, 'Мой первый проект'))
        : saved.first;
    active = project.entry;
    tabs.add(active);
    _controller();
  }

  void _controller() {
    code = CodeController(
      text: project.files[active] ?? '',
      language: switch (active.split('.').last) {
        'c' || 'h' || 'cpp' || 'hpp' => cpp,
        'cs' => cs,
        'py' => python,
        'java' => java,
        'js' => javascript,
        'go' => go,
        'sql' => sql,
        'html' || 'svg' => xml,
        'css' => css,
        _ => null,
      },
    );
    code.addListener(_changed);
  }

  void _changed() {
    project.files[active] = code.fullText;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 650), _save);
  }

  Future<void> _save() async {
    debounce?.cancel();
    try {
      DevProject.decode(project.encode());
      await widget.store.draft('project.${project.id}', project.encode());
      if (mounted && warning != null) setState(() => warning = null);
    } catch (e) {
      if (mounted) setState(() => warning = 'Не удалось сохранить проект: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _save();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    preview.close();
    debounce?.cancel();
    widget.store
        .draft('project.${project.id}', project.encode())
        .catchError((_) {});
    runner.cancel();
    code.removeListener(_changed);
    code.dispose();
    stdin.dispose();
    search.dispose();
    replacement.dispose();
    super.dispose();
  }

  Future<void> _select(String name) async {
    if (name == active || busy) return;
    await _save();
    code.removeListener(_changed);
    code.dispose();
    setState(() {
      active = name;
      if (!tabs.contains(name)) tabs.add(name);
      _controller();
    });
    widget.sounds.cue(SoundCue.navigation);
  }

  Future<void> _load(DevProject value) async {
    await _save();
    if (!mounted) return;
    code.removeListener(_changed);
    code.dispose();
    setState(() {
      project = value;
      active = value.entry;
      tabs
        ..clear()
        ..add(active);
      _controller();
      output = 'Открыт проект ${project.name}.';
    });
  }

  Future<String?> _text(String title, {String initial = ''}) async {
    final c = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
          decoration: const InputDecoration(
            hintText: 'Имя или относительный путь',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    // A dialog route can animate out after its Future completes.
    Future<void>.delayed(const Duration(milliseconds: 400), c.dispose);
    return result?.trim();
  }

  Future<void> _newProject() async {
    String language = project.language;
    final name = TextEditingController(text: 'Новый проект');
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Создать проект'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: language,
                items: languageNames.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => update(() => language = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted) {
      final title = name.text.trim();
      if (title.isEmpty || title.length > 100) {
        setState(() => warning = 'Название должно содержать 1–100 символов.');
      } else {
        await _load(DevProject.create(language, title));
        await _save();
      }
    }
    Future<void>.delayed(const Duration(milliseconds: 400), name.dispose);
  }

  Future<void> _addFile() async {
    final name = await _text('Новый файл', initial: 'helpers/');
    if (name == null || !mounted) return;
    if (!DevProject.validPath(name) ||
        project.files.containsKey(name) ||
        project.files.length >= 40) {
      setState(
        () => warning =
            'Нужен уникальный относительный путь. Максимум 40 файлов.',
      );
      return;
    }
    project.files[name] = '';
    try {
      DevProject.decode(project.encode());
    } catch (e) {
      project.files.remove(name);
      setState(() => warning = '$e');
      return;
    }
    await _select(name);
  }

  Future<void> _renameFile() async {
    final old = active,
        name = await _text('Переименовать файл', initial: active);
    if (name == null || name == old || !mounted) return;
    if (!DevProject.validPath(name) || project.files.containsKey(name)) {
      setState(() => warning = 'Некорректный путь или файл уже существует.');
      return;
    }
    final value = project.files.remove(old)!;
    project.files[name] = value;
    final wasEntry = project.entry == old;
    if (wasEntry) project.entry = name;
    try {
      DevProject.decode(project.encode());
    } catch (e) {
      project.files.remove(name);
      project.files[old] = value;
      if (wasEntry) project.entry = old;
      setState(() => warning = '$e');
      return;
    }
    tabs.remove(old);
    await _select(name);
    await _save();
  }

  Future<void> _deleteFile() async {
    if (active == project.entry) {
      setState(() => warning = 'Сначала выбери другую точку входа.');
      return;
    }
    if (!await confirm(
      context,
      'Удалить $active?',
      'Файл будет удалён из проекта. Сохрани экспорт, если нужна копия.',
    )) {
      return;
    }
    if (!mounted) return;
    final old = active;
    await _select(project.entry);
    setState(() {
      project.files.remove(old);
      tabs.remove(old);
    });
    await _save();
  }

  Future<void> _importLegacy() async {
    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Черновики мастерской 0.1'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: legacyDrafts
                .map(
                  (d) => ListTile(
                    title: Text(
                      languageNames[(d['task'] as String).substring(4)]!,
                    ),
                    subtitle: Text(
                      DateTime.fromMillisecondsSinceEpoch(
                        d['updated'],
                      ).toLocal().toString(),
                    ),
                    onTap: () => Navigator.pop(context, d),
                  ),
                )
                .toList(),
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
    if (chosen != null && mounted) {
      await _load(_fromLegacy(chosen));
      await _save();
    }
  }

  Future<void> _versions() async {
    final candidates = versions
        .where((d) => d['task'] == 'project.${project.id}')
        .toList();
    final selected = await showDialog<DevProject>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Версии проекта с устройств'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: candidates.map((d) {
              final device = d['device'] as String;
              return ListTile(
                title: Text(
                  'Устройство ${device.substring(0, device.length.clamp(0, 6))}',
                ),
                subtitle: Text(
                  DateTime.fromMillisecondsSinceEpoch(
                    d['updated'],
                  ).toLocal().toString(),
                ),
                onTap: () {
                  try {
                    Navigator.pop(context, DevProject.decode(d['text']));
                  } catch (_) {
                    Navigator.pop(context);
                  }
                },
              );
            }).toList(),
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
    if (selected != null && mounted) await _load(selected);
  }

  Future<void> _import() async {
    try {
      final file = await openFile();
      if (file == null) return;
      if (await file.length() > 180000) {
        throw const FormatException('Лимит проекта 180 КБ.');
      }
      final imported = DevProject.decode(await file.readAsString());
      if (mounted) {
        await _load(imported);
        await _save();
      }
    } catch (e) {
      if (mounted) setState(() => warning = 'Импорт: $e');
    }
  }

  Future<void> _run() async {
    if (busy) return;
    if (project.language == 'html' || project.language == 'css') {
      await _save();
      if (warning != null) return;
      try {
        final directory = await project.materialize(widget.store.directory);
        final uri = await preview.open(project);
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('Браузер не открылся. Открой адрес вручную: $uri');
        }
        if (mounted) {
          setState(
            () => output =
                'Файлы сайта: ${directory.path}\nПредпросмотр: $uri\nСохрани изменения и обнови страницу браузера. Файлы обслуживаются только на этом устройстве.',
          );
        }
      } catch (e) {
        if (mounted) setState(() => output = 'Предпросмотр: $e');
      }
      return;
    }
    if (project.language != 'sql' &&
        !widget.store.setting('trustedLocalRun', false)) {
      final yes = await confirm(
        context,
        'Запустить свой проект?',
        'Код выполнится локально с правами приложения и сможет читать и изменять файлы. Запускай собственный код. На Android компиляторы входят в APK; при первом запуске им потребуется место и время на подготовку. На ПК нужен установленный компилятор выбранного языка.',
      );
      if (!yes) return;
      await widget.store.set('trustedLocalRun', true);
    }
    await _save();
    if (!mounted || warning != null) return;
    setState(() {
      busy = true;
      output = 'Сборка и запуск ${project.entry}…';
    });
    widget.sounds.cue(SoundCue.open);
    try {
      final result = await runner.runProject(
        project,
        widget.store.directory,
        stdin.text,
      );
      if (mounted) {
        setState(
          () => output =
              '${result.output}${result.error.isNotEmpty ? '\n${result.error}' : ''}\n\nКод завершения: ${result.exitCode}',
        );
        widget.sounds.cue(result.ok ? SoundCue.success : SoundCue.error);
      }
    } catch (e) {
      if (mounted) setState(() => output = 'Не удалось запустить: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _findNext() {
    final term = search.text;
    if (term.isEmpty) return;
    final start = code.selection.isValid ? code.selection.end : 0;
    var index = code.fullText.indexOf(term, start);
    if (index < 0) index = code.fullText.indexOf(term);
    if (index >= 0) {
      code.selection = TextSelection(
        baseOffset: index,
        extentOffset: index + term.length,
      );
    } else {
      setState(() => warning = 'Совпадений нет.');
    }
  }

  void _replaceAll() {
    if (search.text.isEmpty) return;
    code.text = code.fullText.replaceAll(search.text, replacement.text);
    widget.sounds.cue(SoundCue.save);
  }

  Future<void> _goLine() async {
    final value = await _text('Номер строки');
    final line = int.tryParse(value ?? '');
    if (line == null || line < 1) return;
    final lines = code.fullText.split('\n');
    if (line > lines.length) return;
    final offset = lines
        .take(line - 1)
        .fold<int>(0, (sum, v) => sum + v.length + 1);
    code.selection = TextSelection.collapsed(offset: offset);
  }

  Widget _files() => ListView(
    padding: const EdgeInsets.all(8),
    children: [
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded),
          hintText: 'Файлы',
        ),
        onChanged: (v) => setState(() => filter = v),
      ),
      const SizedBox(height: 8),
      ...((project.files.keys.toList()..sort())
          .where((name) => name.toLowerCase().contains(filter.toLowerCase()))
          .map(
            (name) => ListTile(
              dense: true,
              selected: name == active,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(
                name == project.entry
                    ? Icons.play_circle_outline_rounded
                    : Icons.description_outlined,
                size: 18,
              ),
              title: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                ),
              ),
              onTap: busy
                  ? null
                  : () {
                      _select(name);
                      if (MediaQuery.sizeOf(context).width < 1100) {
                        Navigator.pop(context);
                      }
                    },
            ),
          )),
      TextButton.icon(
        onPressed: busy ? null : _addFile,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Новый файл'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: tabs
                .map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InputChip(
                      label: Text(name.split('/').last),
                      selected: name == active,
                      onPressed: busy ? null : () => _select(name),
                      onDeleted: tabs.length <= 1 || busy
                          ? null
                          : () {
                              if (name == active) {
                                _select(tabs.firstWhere((n) => n != name));
                              }
                              setState(() => tabs.remove(name));
                            },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        if (find)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      labelText: 'Найти',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _findNext(),
                  ),
                ),
                IconButton(
                  onPressed: _findNext,
                  icon: const Icon(Icons.navigate_next_rounded),
                  tooltip: 'Следующее совпадение',
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: replacement,
                    decoration: const InputDecoration(
                      labelText: 'Заменить на',
                      isDense: true,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : _replaceAll,
                  child: const Text('Заменить все'),
                ),
                IconButton(
                  onPressed: () => setState(() => find = false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CodeTheme(
              data: CodeThemeData(
                styles: {
                  'root': TextStyle(
                    color: scheme.onSurface,
                    backgroundColor: scheme.surfaceContainerLowest,
                  ),
                  'keyword': TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  'string': TextStyle(color: scheme.tertiary),
                  'number': TextStyle(color: scheme.secondary),
                  'comment': TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                },
              ),
              child: CodeField(
                controller: code,
                expands: true,
                minLines: null,
                maxLines: null,
                readOnly: busy,
                background: scheme.surfaceContainerLowest,
                gutterStyle: GutterStyle(
                  width: 48,
                  showFoldingHandles: true,
                  showErrors: false,
                  background: scheme.surfaceContainerLow,
                ),
                textStyle: TextStyle(
                  fontFamily: widget.store.setting(
                    'editorFont',
                    'JetBrainsMono',
                  ),
                  fontSize: widget.store
                      .setting<num>('editorSize', 14)
                      .toDouble(),
                  height: 1.55,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${code.fullText.split('\n').length} строк · ${project.files.length} файлов · ${languageNames[project.language]} · сохраняется локально',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TextField(
            controller: stdin,
            maxLines: 1,
            decoration: const InputDecoration(
              labelText: 'Стандартный ввод (stdin)',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: Panel(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: SelectableText(
                output,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
    final view = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!wide)
                IconButton(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => SizedBox(height: 420, child: _files()),
                  ),
                  icon: const Icon(Icons.folder_open_rounded),
                  tooltip: 'Файлы проекта',
                ),
              Text(project.name, style: Theme.of(context).textTheme.titleLarge),
              PopupMenuButton<DevProject>(
                enabled: !busy,
                tooltip: 'Открыть проект',
                icon: const Icon(Icons.unfold_more_rounded),
                itemBuilder: (_) => projects
                    .map(
                      (p) => PopupMenuItem(
                        value: p,
                        child: Text('${p.name} · ${languageNames[p.language]}'),
                      ),
                    )
                    .toList(),
                onSelected: busy ? null : _load,
              ),
              FilledButton.icon(
                onPressed: busy ? null : _run,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Запустить проект'),
              ),
              if (busy)
                OutlinedButton.icon(
                  onPressed: runner.cancel,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Стоп'),
                ),
              IconButton(
                onPressed: () => setState(() => find = !find),
                icon: const Icon(Icons.find_replace_rounded),
                tooltip: 'Поиск и замена · Ctrl+F',
              ),
              IconButton(
                onPressed: () async {
                  await _save();
                  widget.sounds.cue(SoundCue.save);
                },
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Сохранить · Ctrl+S',
              ),
              PopupMenuButton<String>(
                enabled: !busy,
                tooltip: 'Действия проекта',
                onSelected: (value) async {
                  switch (value) {
                    case 'new':
                      await _newProject();
                    case 'file':
                      await _addFile();
                    case 'rename':
                      await _renameFile();
                    case 'delete':
                      await _deleteFile();
                    case 'entry':
                      setState(() => project.entry = active);
                      await _save();
                    case 'line':
                      await _goLine();
                    case 'legacy':
                      await _importLegacy();
                    case 'versions':
                      await _versions();
                    case 'import':
                      await _import();
                    case 'export':
                      await _save();
                      if (context.mounted) {
                        await exportText(
                          context,
                          widget.store.directory,
                          '${project.id}.devcat-project.json',
                          project.encode(),
                        );
                      }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'new', child: Text('Новый проект')),
                  PopupMenuItem(value: 'file', child: Text('Добавить файл')),
                  PopupMenuItem(
                    value: 'rename',
                    child: Text('Переименовать файл'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Удалить файл')),
                  PopupMenuItem(
                    value: 'entry',
                    child: Text('Сделать точкой входа'),
                  ),
                  PopupMenuItem(value: 'line', child: Text('Перейти к строке')),
                  if (legacyDrafts.isNotEmpty)
                    const PopupMenuItem(
                      value: 'legacy',
                      child: Text('Черновики мастерской 0.1'),
                    ),
                  PopupMenuItem(
                    value: 'versions',
                    child: Text('Версии с устройств'),
                  ),
                  PopupMenuItem(value: 'import', child: Text('Импорт проекта')),
                  PopupMenuItem(
                    value: 'export',
                    child: Text('Экспорт проекта'),
                  ),
                ],
              ),
            ],
          ),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(warning!, style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: wide
                ? Row(
                    children: [
                      SizedBox(width: 220, child: _files()),
                      const VerticalDivider(width: 20),
                      Expanded(child: editor),
                    ],
                  )
                : editor,
          ),
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _save(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            setState(() => find = !find),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _run,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            _save(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            setState(() => find = !find),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, bounds) => bounds.maxHeight < 590
              ? SingleChildScrollView(child: SizedBox(height: 590, child: view))
              : view,
        ),
      ),
    );
  }
}
