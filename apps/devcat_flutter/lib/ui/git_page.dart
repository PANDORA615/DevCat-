import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/course.dart';
import 'lecture.dart';
import 'package:flutter/material.dart';
import '../core/git_lab.dart';
import '../core/store.dart';
import '../core/sound.dart';
import 'widgets.dart';

class GitPage extends StatefulWidget {
  final AppStore store;
  final SoftSounds sounds;
  const GitPage({super.key, required this.store, required this.sounds});
  @override
  State<GitPage> createState() => _GitPageState();
}

class _GitPageState extends State<GitPage> {
  final command = TextEditingController(text: 'git init');
  late final GitLab lab;
  String output = 'Локальный учебный репозиторий. README.md уже создан.\n';
  bool busy = false;
  final readme = TextEditingController();
  String fileMessage = '';
  Future<void> _loadReadme() async {
    await lab.initialize();
    final text = await File('${lab.directory.path}/README.md').readAsString();
    if (mounted) setState(() => readme.text = text);
  }

  Future<void> _saveReadme() async {
    try {
      await File('${lab.directory.path}/README.md').writeAsString(readme.text);
      if (mounted) {
        setState(
          () => fileMessage =
              'README.md сохранён в рабочей папке. Теперь сравни git diff.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => fileMessage = 'Не удалось сохранить: $e');
    }
  }

  bool get supported =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  @override
  void initState() {
    super.initState();
    lab = GitLab(Directory('${widget.store.directory.path}/git-lab'));
    if (supported) _loadReadme();
  }

  @override
  void dispose() {
    command.dispose();
    readme.dispose();
    lab.runner.cancel();
    super.dispose();
  }

  Future<void> _execute() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await lab.initialize();
      final result = await lab.execute(command.text);
      if (mounted) {
        setState(
          () =>
              output += '\n\$ ${command.text}\n${result.output}${result.error}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => output += '\n$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      const PageHeading(
        'Сохрани первый шаг.',
        'Git хранит историю. GitHub помогает делиться ею.',
        eyebrow: 'ОТДЕЛЬНЫЙ УЧЕБНЫЙ ТРЕК',
      ),
      FutureBuilder<String>(
        future: rootBundle.loadString('assets/content/git_course.json'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final course = Course(jsonDecode(snapshot.data!));
          return ExpansionTile(
            title: const Text('Полный курс Git и GitHub с нуля'),
            subtitle: const Text(
              '20 занятий · Git на ПК · GitHub на ПК и телефоне',
            ),
            children: course.lessons
                .map(
                  (lesson) => ListTile(
                    title: Text(lesson.title),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(lesson.title)),
                          body: LectureView(
                            lesson: lesson,
                            course: course,
                            store: widget.store,
                            onPractice: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
      const SizedBox(height: 18),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Первый коммит',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Working tree — текущие файлы. Index (staging) — выбранные изменения для следующего снимка. Repository хранит коммиты. git add добавляет содержимое в index, git commit создаёт снимок с сообщением.\n\nGit работает локально. GitHub — отдельный сетевой сервис. Для первого коммита он не нужен.',
              style: TextStyle(height: 1.7),
            ),
            const SizedBox(height: 18),
            const SelectableText(
              'git init\ngit status\ngit add README.md\ngit commit -m "Initial commit"\ngit log --oneline',
              style: TextStyle(fontFamily: 'monospace', height: 1.8),
            ),
            const SizedBox(height: 18),
            const Text(
              'Две типичные ошибки\n• «nothing to commit»: проверь git status, затем добавь файл в index.\n• «Author identity unknown»: настрой user.name и user.email. В этой лаборатории используется локальная учебная личность, системная конфигурация не меняется.',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 12),
            const SelectableText(
              'Источник: https://git-scm.com/book/ru/v2',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      TextButton.icon(
        onPressed: () => launchUrl(
          Uri.parse('https://github.com/PANDORA615/DevCat-'),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.open_in_browser),
        label: const Text('Открыть пример репозитория на GitHub'),
      ),
      if (supported)
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Редактор README.md учебного репозитория'),
              const SizedBox(height: 12),
              TextField(
                controller: readme,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Содержимое README.md',
                ),
              ),
              TextButton(
                onPressed: busy ? null : _saveReadme,
                child: const Text('Сохранить файл перед git add'),
              ),
              if (fileMessage.isNotEmpty) Text(fileMessage),
            ],
          ),
        ),
      const SizedBox(height: 18),
      if (!supported)
        const Panel(
          child: Text(
            'Git-команды выполняем на компьютере. Практику GitHub из полного курса можно выполнять в браузере компьютера или телефона под своим аккаунтом.',
          ),
        ),
      if (supported)
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Настоящий Git · отдельный локальный репозиторий',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: command,
                onSubmitted: (_) => _execute(),
                decoration: const InputDecoration(
                  prefixText: '> ',
                  labelText: 'Команда Git',
                ),
                enabled: !busy,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : _execute,
                    icon: const Icon(Icons.terminal_rounded),
                    label: const Text('Выполнить'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              final passed = await lab.verify();
                              await widget.store.record(
                                'git.basics.first_commit',
                                'git',
                                passed,
                              );
                              await widget.sounds.result(passed);
                              if (mounted) {
                                setState(
                                  () => output +=
                                      '\n${passed ? '✓ HEAD существует, README.md входит в коммит. Задание выполнено!' : '× Не найден коммит с README.md. Выполни add и commit, затем проверь снова.'}\n',
                                );
                              }
                            } catch (e) {
                              if (mounted) setState(() => output += '\n$e');
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Проверить репозиторий'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: SelectableText(
                    output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Здесь выполняются локальные команды Git. Практика GitHub, push и PR описана в полном курсе: браузер и обычный терминал собственного проекта.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
    ],
  );
}
