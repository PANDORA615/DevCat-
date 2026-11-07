import 'motion.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/content_runtime.dart';
import '../core/desktop_updates.dart';
import '../core/project_flush.dart';
import '../core/store.dart';
import '../core/sound.dart';
import '../core/update_download.dart';
import 'cat_actor.dart';
import 'widgets.dart';

class UpdatesPage extends StatefulWidget {
  final AppStore store;
  const UpdatesPage({super.key, required this.store});
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  DesktopUpdates? get updates => DesktopUpdates.current;
  String? selected;
  File? downloaded;
  UpdateFile? downloadedDescription;
  bool opening = false;
  String? localError;

  String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  String _format(UpdateFile file) {
    if (file.name.endsWith('-setup.exe')) return 'Установщик Windows';
    if (file.name.endsWith('.dmg')) return 'Образ macOS';
    if (file.name.endsWith('.deb')) return 'Debian / Ubuntu';
    if (file.name.contains('fedora')) return 'Fedora';
    if (file.name.contains('opensuse')) return 'openSUSE';
    if (file.name.endsWith('.pkg.tar.zst')) return 'Arch Linux';
    if (file.name.endsWith('.AppImage')) return 'AppImage';
    return 'Переносимый архив';
  }

  Future<void> _operation(Future<void> Function() action) async {
    SoundScope.of(context)?.cue(SoundCue.tap);
    await action();
    if (!mounted) return;
    final cue = switch (updates?.phase) {
      'available' => SoundCue.notification,
      'installed' || 'verified' => SoundCue.update,
      'error' => SoundCue.error,
      _ => null,
    };
    if (cue != null) SoundScope.of(context)?.cue(cue);
  }

  Future<void> _import() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Обновление DevCat', extensions: ['json']),
      ],
    );
    if (file != null && mounted && updates != null) {
      await _operation(() => updates!.importContent(File(file.path)));
    }
  }

  Future<void> _openInstaller(UpdateFile description) async {
    final file = downloaded;
    if (file == null || opening) return;
    setState(() {
      opening = true;
      localError = null;
    });
    try {
      if (!await file.exists() || await file.length() != description.bytes) {
        throw const FormatException(
          'Файл установки изменён. Скачай его заново.',
        );
      }
      final digest = await updateFileSha256(file);
      if (digest != description.sha256) {
        throw const FormatException(
          'Файл установки не прошёл проверку. Скачай его заново.',
        );
      }
      await ProjectFlush.saveAll();
      await widget.store.save();
      if (!mounted) return;
      final native =
          Platform.isWindows && file.path.endsWith('.exe') ||
          Platform.isMacOS && file.path.endsWith('.dmg') ||
          Platform.isLinux &&
              (file.path.endsWith('.deb') || file.path.endsWith('.rpm'));
      final yes = await showDevCatDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            native ? 'Открыть установщик?' : 'Открыть папку с обновлением?',
          ),
          content: Text(
            native
                ? 'Открытые проекты сохранены. Установка может попросить закрыть DevCat и подтвердить действие в системе.'
                : file.path.endsWith('.pkg.tar.zst')
                ? 'Открытые проекты сохранены. Установи пакет через менеджер Arch Linux (pacman -U), затем перезапусти DevCat. Прогресс хранится отдельно.'
                : file.path.endsWith('.AppImage')
                ? 'Открытые проекты сохранены. Закрой DevCat и замени AppImage новым файлом. Сохрани прежний файл для отката. Прогресс хранится отдельно.'
                : 'Открытые проекты сохранены. Распакуй новую версию в отдельную папку, закрой DevCat и запусти её оттуда. Сохрани прежнюю папку для отката. Прогресс хранится отдельно.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      if (Platform.isWindows) {
        await Process.start(
          native ? file.path : 'explorer.exe',
          native ? const [] : [file.parent.path],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isMacOS) {
        await Process.start('/usr/bin/open', [
          native ? file.path : file.parent.path,
        ], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [
          native ? file.path : file.parent.path,
        ], mode: ProcessStartMode.detached);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => localError = error is FormatException
              ? error.message.toString()
              : error is StateError
              ? error.message.toString()
              : 'Не удалось открыть установщик. Файл сохранён; попробуй открыть его через файловый менеджер.',
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = updates;
    if (service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Обновления')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ContentRuntime.startupNotice ??
                      'Обновления доступны в полной ПК-версии DevCat.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://github.com/PANDORA615/DevCat-/releases'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Открыть выпуски DevCat'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final busy = service.busy || opening;
        final files = service.appFiles;
        final chosen = files.isEmpty
            ? null
            : files.firstWhere(
                (f) => f.name == selected,
                orElse: () => files.first,
              );
        return Scaffold(
          appBar: AppBar(title: const Text('Обновления DevCat')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'DevCat ${service.runtime.appVersion}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Panel(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CatActor(size: 72, action: service.mascotAction),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            service.status,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (service.total > 0 && service.phase == 'downloading') ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: (service.received / service.total).clamp(0, 1),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_size(service.received)} из ${_size(service.total)}',
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () => _operation(
                                () => service.check(
                                  beta:
                                      widget.store.setting(
                                        'updateChannel',
                                        'beta',
                                      ) ==
                                      'beta',
                                ),
                              ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Проверить обновления'),
                      ),
                      if (service.phase == 'downloading' ||
                          service.phase == 'checking')
                        TextButton(
                          onPressed: service.cancel,
                          child: const Text('Отменить'),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Проверять обновления при запуске'),
                    subtitle: const Text(
                      'Проверка не мешает урокам. Скачивание начинается по твоему выбору.',
                    ),
                    value: widget.store.setting('autoCheckUpdates', true),
                    onChanged: busy
                        ? null
                        : (value) async {
                            await widget.store.set('autoCheckUpdates', value);
                            if (mounted) setState(() {});
                          },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: widget.store.setting('updateChannel', 'beta'),
                    decoration: const InputDecoration(
                      labelText: 'Канал выпусков',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'stable',
                        child: Text('Стабильные'),
                      ),
                      DropdownMenuItem(
                        value: 'beta',
                        child: Text('Включая предварительные'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) async {
                            if (value != null) {
                              await widget.store.set('updateChannel', value);
                              if (mounted) setState(() {});
                            }
                          },
                  ),
                  if (service.plan != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Выпуск ${service.plan!.version}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(service.plan!.notes),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Уроки и иллюстрации',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Проверенные данные применяются после следующего запуска. Проекты и прогресс не заменяются.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.tonal(
                        onPressed: busy || !service.hasContentUpdate
                            ? null
                            : () => _operation(service.installContent),
                        child: Text(
                          service.hasContentUpdate
                              ? 'Скачать уроки · ${_size(service.plan!.content.bytes)}'
                              : 'Уроки актуальны',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: busy ? null : _import,
                        child: const Text('Установить пакет из файла'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final yes = await showDevCatDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text(
                                      'Вернуться к предыдущим урокам?',
                                    ),
                                    content: const Text(
                                      'Прогресс и проекты сохранятся. Изменение появится после следующего запуска.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Отмена'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Вернуться'),
                                      ),
                                    ],
                                  ),
                                );
                                if (yes == true) await service.rollback();
                              },
                        child: const Text('Предыдущая версия уроков'),
                      ),
                    ],
                  ),
                  if (service.hasAppUpdate && chosen != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Приложение',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(service.plan!.version),
                      initialValue: chosen.name,
                      decoration: const InputDecoration(labelText: 'Формат'),
                      isExpanded: true,
                      items: files
                          .map(
                            (f) => DropdownMenuItem(
                              value: f.name,
                              child: Text('${_format(f)} · ${_size(f.bytes)}'),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (value) => setState(() => selected = value),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => _operation(() async {
                                  final result = await service.downloadApp(
                                    chosen,
                                  );
                                  if (result != null && mounted) {
                                    setState(() {
                                      downloaded = result;
                                      downloadedDescription = chosen;
                                    });
                                  }
                                }),
                          child: const Text('Скачать приложение'),
                        ),
                        OutlinedButton(
                          onPressed:
                              busy ||
                                  downloaded == null ||
                                  downloadedDescription?.sha256 != chosen.sha256
                              ? null
                              : () => _openInstaller(chosen),
                          child: const Text('Открыть установку'),
                        ),
                      ],
                    ),
                  ],
                  if (localError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        localError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
