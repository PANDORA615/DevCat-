import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/progress.dart';
import '../core/runner.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/sync.dart';
import 'transfer.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  final AppStore store;
  final SoftSounds sounds;
  final VoidCallback onSynced;
  const SettingsPage({
    super.key,
    required this.store,
    required this.sounds,
    required this.onSynced,
  });
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final password = TextEditingController();
  late TextEditingController url, user, hex;
  final vault = const FlutterSecureStorage();
  bool syncing = false, savePassword = false;
  String status = '', toolchains = '';
  @override
  void initState() {
    super.initState();
    url = TextEditingController(text: widget.store.setting('syncUrl', ''));
    user = TextEditingController(text: widget.store.setting('syncUser', ''));
    hex = TextEditingController(
      text: widget.store
          .setting('seedColor', 0xff416c57)
          .toRadixString(16)
          .substring(2),
    );
    _loadPassword();
  }

  Future<void> _loadPassword() async {
    try {
      final saved = await vault.read(key: 'devcat.webdav');
      if (saved != null && mounted) {
        final j = jsonDecode(saved);
        if (j['url'] == url.text && j['user'] == user.text) {
          setState(() {
            password.text = j['password'];
            savePassword = true;
          });
        }
      }
    } catch (_) {
      /* Secret service may be unavailable: session-only password remains usable. */
    }
  }

  @override
  void dispose() {
    url.dispose();
    user.dispose();
    hex.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    if (syncing) return;
    setState(() {
      syncing = true;
      status = 'Объединяю прогресс…';
    });
    try {
      await widget.store.set('syncUrl', url.text.trim());
      await widget.store.set('syncUser', user.text);
      await SyncClient().synchronize(
        url.text,
        user.text,
        password.text,
        () async => widget.store.progress,
        widget.store.merge,
      );
      String credentialNote = '';
      try {
        if (savePassword) {
          await vault.write(
            key: 'devcat.webdav',
            value: jsonEncode({
              'url': url.text,
              'user': user.text,
              'password': password.text,
            }),
          );
        } else {
          await vault.delete(key: 'devcat.webdav');
        }
      } catch (_) {
        credentialNote =
            ' Пароль не сохранён: системное хранилище ключей недоступно.';
      }
      await widget.store.set('lastSync', DateTime.now().toIso8601String());
      if (mounted) {
        setState(
          () =>
              status = 'Прогресс и черновики синхронизированы.$credentialNote',
        );
        widget.onSynced();
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Синхронизация не завершена: $e');
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> _import() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Прогресс DevCat',
            extensions: ['json'],
            mimeTypes: ['application/json'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 5 * 1024 * 1024) {
        throw const FormatException('Файл больше 5 МиБ.');
      }
      final data = ProgressData.decode(await file.readAsString());
      if (!mounted) return;
      if (await confirm(
        context,
        'Объединить прогресс?',
        'В копии ${data.attempts.length} попыток и ${data.drafts.length} черновиков. Результаты этого устройства сохранятся.',
      )) {
        await widget.store.merge(data);
        if (mounted) {
          setState(() => status = 'Резервная копия импортирована.');
          widget.onSynced();
        }
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Импорт отменён: $e');
    }
  }

  Widget _title(BuildContext context, IconData icon, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const PageHeading(
          'Устройся поудобнее.',
          'Твой цвет, твой ритм, твои данные.',
          eyebrow: 'НАСТРОЙКИ',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(context, Icons.palette_outlined, 'Внешний вид'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in {
                    'system': 'Системная',
                    'light': 'Светлая',
                    'dark': 'Тёмная',
                  }.entries)
                    ChoiceChip(
                      label: Text(mode.value),
                      selected: store.setting('theme', 'system') == mode.key,
                      onSelected: (_) => store.set('theme', mode.key),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final c in <int, String>{
                    0xff416c57: 'Шалфей',
                    0xff376493: 'Небо',
                    0xffa15c35: 'Терракота',
                    0xff8b5368: 'Роза',
                    0xff526367: 'Нейтральная',
                  }.entries)
                    ActionChip(
                      avatar: CircleAvatar(
                        backgroundColor: Color(c.key),
                        radius: 8,
                      ),
                      label: Text(c.value),
                      onPressed: () {
                        store.set('seedColor', c.key);
                        hex.text = c.key.toRadixString(16).substring(2);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: hex,
                  decoration: InputDecoration(
                    labelText: 'Свой цвет Material · HEX',
                    prefixText: '#',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check_rounded),
                      tooltip: 'Применить цвет',
                      onPressed: () {
                        final value = hex.text.replaceAll('#', '');
                        if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
                          store.set(
                            'seedColor',
                            0xff000000 | int.parse(value, radix: 16),
                          );
                        } else {
                          setState(
                            () => status =
                                'HEX должен содержать 6 знаков, например 416c57.',
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Цвета устройства Material You'),
                subtitle: const Text(
                  'Если система поддерживает динамическую палитру',
                ),
                value: store.setting('dynamicColor', false),
                onChanged: (v) => store.set('dynamicColor', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Повышенный контраст'),
                value: store.setting('highContrast', false),
                onChanged: (v) => store.set('highContrast', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Уменьшить движение'),
                subtitle: const Text('Мгновенные переходы и реплики кота'),
                value: store.setting('reducedMotion', false),
                onChanged: (v) => store.set('reducedMotion', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Показывать кота-наставника'),
                value: store.setting('cat', true),
                onChanged: (v) => store.set('cat', v),
              ),
              const Divider(),
              Text(
                'Размер шрифта редактора: ${store.setting<num>('editorSize', 14).round()}',
              ),
              Slider(
                value: store.setting<num>('editorSize', 14).toDouble(),
                min: 12,
                max: 24,
                divisions: 12,
                onChanged: (v) => store.set('editorSize', v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(context, Icons.music_note_outlined, 'Тихие звуки'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Звуки касаний и результатов'),
                subtitle: const Text(
                  'Собственные мягкие сигналы без сторонних семплов',
                ),
                value: store.setting('sound', true),
                onChanged: (v) => store.set('sound', v),
              ),
              Row(
                children: [
                  const Icon(Icons.volume_down_outlined),
                  Expanded(
                    child: Slider(
                      value: store.setting<num>('volume', .22).toDouble(),
                      min: 0,
                      max: 1,
                      onChanged: (v) => store.set('volume', v),
                      onChangeEnd: (_) => widget.sounds.tap(),
                    ),
                  ),
                  const Icon(Icons.volume_up_outlined),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(
                context,
                Icons.devices_rounded,
                'Продолжить на другом устройстве',
              ),
              const Text(
                'Подключи одну и ту же папку личного WebDAV (например, Nextcloud) на компьютере и телефоне. После занятия нажми «Синхронизировать», затем сделай это на другом устройстве. Нужны интернет и HTTPS. Отправляются прогресс, позиция курса и учебные черновики; пароль и настройки остаются на устройстве.',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'HTTPS URL существующей папки WebDAV',
                  hintText:
                      'https://cloud.example/remote.php/dav/files/user/DevCat/',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: user,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Пользователь'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Пароль приложения WebDAV',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Сохранить пароль в хранилище ключей ОС'),
                value: savePassword,
                onChanged: (v) => setState(() => savePassword = v ?? false),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: syncing ? null : _sync,
                    icon: syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(
                      syncing ? 'Синхронизация…' : 'Синхронизировать',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await vault.delete(key: 'devcat.webdav');
                        password.clear();
                        setState(() => savePassword = false);
                      } catch (e) {
                        setState(() => status = 'Хранилище ключей: $e');
                      }
                    },
                    child: const Text('Забыть пароль'),
                  ),
                ],
              ),
              if (store.settings['lastSync'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Последняя синхронизация: ${store.settings['lastSync']}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SelectableText(status),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(
                context,
                Icons.folder_outlined,
                'Данные под твоим контролем',
              ),
              const Text(
                'Экспорт содержит прогресс и код учебных черновиков. Храни копию в надёжном месте. При импорте записи объединяются, а черновики разных устройств сохраняются отдельно.',
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await store.flush();
                        if (!context.mounted) return;
                        await exportText(
                          context,
                          store.directory,
                          'devcat-progress.json',
                          store.progress.encode(),
                        );
                      } catch (e) {
                        if (mounted) setState(() => status = 'Экспорт: $e');
                      }
                    },
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Экспорт прогресса'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Импортировать'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Удалить локальный прогресс?',
                        'Прогресс и черновики этого устройства будут очищены. Сделай экспорт перед удалением. Файл WebDAV и другие устройства не очищаются; следующая синхронизация может вернуть данные.',
                      )) {
                        store.progress = ProgressData();
                        await store.save();
                        if (mounted) {
                          setState(() => status = 'Локальный прогресс очищен.');
                        }
                      }
                    },
                    child: const Text('Очистить локальный прогресс'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SelectableText(
                'Каталог данных: ${store.directory.path}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(context, Icons.terminal_rounded, 'Среда исполнения'),
              const Text(
                'SQLite встроен. На ПК остальные языки используют установленные системные компиляторы. Запуск работает с правами твоего пользователя; используй собственный код. Полноценная изоляция, LSP и отладчик пока не реализованы.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  setState(() => toolchains = 'Проверяю PATH…');
                  final result = await LocalRunner().toolchains();
                  if (mounted) {
                    setState(
                      () => toolchains = result.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('\n'),
                    );
                  }
                },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Показать версии toolchain'),
              ),
              if (toolchains.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: SelectableText(toolchains),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Разрешён запуск собственного локального кода',
                ),
                value: store.setting('trustedLocalRun', false),
                onChanged: (v) async {
                  if (!v ||
                      await confirm(
                        context,
                        'Разрешить запуск?',
                        'Код выполняется с твоими правами. Сторонние программы могут читать и менять файлы.',
                      )) {
                    await store.set('trustedLocalRun', v);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'DevCat 0.1.0 · MIT · Без аналитики и облачного ИИ\nЭто вводный релиз. Полный список ограничений — в README репозитория.',
          style: TextStyle(fontSize: 12, height: 1.6),
        ),
      ],
    );
  }
}
