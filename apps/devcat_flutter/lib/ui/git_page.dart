import 'dart:io';
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
  bool get supported =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  @override
  void initState() {
    super.initState();
    lab = GitLab(Directory('${widget.store.directory.path}/git-lab'));
    if (supported) lab.initialize();
  }

  @override
  void dispose() {
    command.dispose();
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
      const SizedBox(height: 18),
      if (!supported)
        const Panel(
          child: Text(
            'На Android доступна теория Git. Настоящая локальная Git-лаборатория в релизе 0.1 работает на ПК; симулятор не подменяет реальные команды.',
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
                'Доступны только локальные учебные команды. Подключение GitHub OAuth, push и PR в 0.1 не реализованы.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
    ],
  );
}
