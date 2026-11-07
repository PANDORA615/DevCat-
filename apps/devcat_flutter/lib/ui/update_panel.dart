import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_version.dart';
import '../core/store.dart';
import '../core/sound.dart';
import '../core/updates.dart';

class UpdatePanel extends StatefulWidget {
  final AppStore store;
  final SoftSounds sounds;
  const UpdatePanel({super.key, required this.store, required this.sounds});
  @override
  State<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> {
  final service = UpdateService();
  late final owner = TextEditingController(
    text: widget.store.setting('updateOwner', 'PANDORA615'),
  );
  late final repo = TextEditingController(
    text: widget.store.setting('updateRepo', 'DevCat-'),
  );
  String status = '';
  bool busy = false;
  VerifiedUpdate? update;
  @override
  void dispose() {
    service.dispose();
    owner.dispose();
    repo.dispose();
    super.dispose();
  }

  Future<void> check() async {
    setState(() {
      busy = true;
      status = 'Проверка подписи обновления…';
      update = null;
    });
    try {
      await widget.store.updateSettings({
        'updateOwner': owner.text.trim(),
        'updateRepo': repo.text.trim(),
      });
      final result = await service.check(
        owner: owner.text.trim(),
        repo: repo.text.trim(),
        channel: widget.store.setting('updateChannel', 'stable'),
      );
      if (!mounted) return;
      setState(() {
        update = result;
        status =
            AppVersion(result.version).compareTo(AppVersion(appVersion)) > 0
            ? 'Доступна версия ${result.version}'
            : 'Версия приложения актуальна';
      });
      if (AppVersion(result.version).compareTo(AppVersion(appVersion)) > 0) {
        widget.sounds.cue(SoundCue.update);
      }
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Не удалось проверить обновление: $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Обновления · DevCat $appVersion',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: owner,
        decoration: const InputDecoration(labelText: 'Владелец GitHub'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: repo,
        decoration: const InputDecoration(labelText: 'Репозиторий обновлений'),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: widget.store.setting('updateChannel', 'stable'),
        decoration: const InputDecoration(labelText: 'Канал'),
        items: const [
          DropdownMenuItem(value: 'stable', child: Text('Стабильный')),
          DropdownMenuItem(value: 'beta', child: Text('Бета')),
        ],
        onChanged: busy
            ? null
            : (v) {
                if (v != null) {
                  widget.store.set('updateChannel', v);
                  setState(() => update = null);
                }
              },
      ),
      const SizedBox(height: 12),
      if (!service.configured)
        const Text(
          'Подписанные OTA-обновления ещё не настроены владельцем сборки. Установщики доступны в GitHub Releases.',
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: busy || !service.configured ? null : check,
            child: Text(busy ? 'Проверка…' : 'Проверить обновления'),
          ),
          OutlinedButton(
            onPressed: () async {
              final uri = Uri.https(
                'github.com',
                '/${owner.text.trim()}/${repo.text.trim()}/releases',
              );
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: const Text('Открыть релизы'),
          ),
          if (update?.content != null)
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await service.installContent(update!, widget.store);
                        if (mounted) {
                          setState(
                            () => status =
                                'Курсы обновлены. Перезапусти приложение для применения.',
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(
                            () => status =
                                'Обновление отменено, текущие курсы сохранены: $e',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: const Text('Скачать и проверить курсы'),
            ),
          if (widget.store.setting<String?>('contentUpdateActive', null) !=
              null)
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await UpdateService.rollback(widget.store);
                        if (mounted) {
                          setState(
                            () => status =
                                'Восстановлена предыдущая версия. Перезапусти приложение.',
                          );
                        }
                      } catch (error) {
                        if (mounted) {
                          setState(
                            () => status = 'Не удалось сохранить откат: $error',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: const Text('Откатить курсы'),
            ),
        ],
      ),
      if (update != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(update!.notes),
        ),
      if (status.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(status)),
    ],
  );
}
