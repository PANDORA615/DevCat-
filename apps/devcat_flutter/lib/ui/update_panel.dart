import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_version.dart';
import '../core/store.dart';
import '../core/sound.dart';
import '../core/updates.dart';

class UpdatePanel extends StatefulWidget {
  final AppStore store;
  final SoftSounds sounds;
  final UpdateService Function()? serviceFactory;
  const UpdatePanel({
    super.key,
    required this.store,
    required this.sounds,
    this.serviceFactory,
  });
  @override
  State<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> {
  late final service = widget.serviceFactory?.call() ?? UpdateService();
  UpdateCancellation? cancellation;
  UpdateDownloadProgress? progress;
  bool installing = false, checking = false;
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
    cancellation?.cancel();
    service.dispose();
    owner.dispose();
    repo.dispose();
    super.dispose();
  }

  Future<void> check() async {
    setState(() {
      busy = true;
      checking = true;
      status = 'Проверка подписи обновления…';
      cancellation = UpdateCancellation();
      progress = null;
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
        cancellation: cancellation,
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
    } on UpdateCancelled {
      if (mounted) setState(() => status = 'Проверка отменена');
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Не удалось проверить обновление: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          checking = false;
        });
      }
    }
  }

  Future<void> install() async {
    final plan = update;
    if (plan == null || busy) return;
    final token = UpdateCancellation();
    setState(() {
      busy = true;
      installing = true;
      cancellation = token;
      progress = null;
      status = 'Загрузка курсов…';
    });
    try {
      await service.installContent(
        plan,
        widget.store,
        cancellation: token,
        onProgress: (value) {
          if (mounted) {
            setState(() {
              progress = value;
              status = value.fraction == 1
                  ? 'Проверка курсов…'
                  : 'Загрузка курсов…';
            });
          }
        },
      );
      if (mounted) {
        setState(
          () => status =
              'Курсы обновлены. Перезапусти приложение для применения.',
        );
      }
    } on UpdateCancelled {
      if (mounted) {
        setState(() => status = 'Загрузка отменена. Текущие курсы сохранены.');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => status =
              'Не удалось обновить курсы. Текущая версия сохранена: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          installing = false;
        });
      }
    }
  }

  String formatBytes(num bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} КБ'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';

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
        enabled: !busy,
        decoration: const InputDecoration(labelText: 'Владелец GitHub'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: repo,
        enabled: !busy,
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
            child: const Text('Проверить обновления'),
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
              onPressed: busy ? null : install,
              child: const Text('Скачать и проверить курсы'),
            ),
          if (busy && (checking || (installing && progress?.fraction != 1)))
            TextButton(
              onPressed: cancellation?.isCancelled == true
                  ? null
                  : () {
                      cancellation?.cancel();
                      setState(() => status = 'Отмена…');
                    },
              child: const Text('Отменить загрузку'),
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
      if (busy) ...[
        const SizedBox(height: 12),
        LinearProgressIndicator(value: installing ? progress?.fraction : null),
        if (installing && progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${formatBytes(progress!.received)}${progress!.total == null ? '' : ' / ${formatBytes(progress!.total!)} · ${(progress!.fraction! * 100).floor()}%'} · ${formatBytes(progress!.bytesPerSecond)}/с',
            ),
          ),
      ],
      if (update?.content != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Размер курсов: ${formatBytes(update!.content!.size)}. Для применения нужен перезапуск.',
          ),
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
