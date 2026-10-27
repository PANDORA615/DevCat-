import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/nearby_sync.dart';
import '../core/store.dart';
import '../core/sound.dart';
import 'widgets.dart';

class NearbyPanel extends StatefulWidget {
  final AppStore store;
  final VoidCallback onSynced;
  const NearbyPanel({super.key, required this.store, required this.onSynced});
  @override
  State<NearbyPanel> createState() => _NearbyPanelState();
}

class _NearbyPanelState extends State<NearbyPanel> {
  late final NearbySync sync;
  final code = TextEditingController();
  String? offered;
  String status = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    sync = NearbySync(
      widget.store,
      onStatus: (text) {
        if (mounted) {
          setState(() => status = text);
          widget.onSynced();
        }
      },
    );
  }

  @override
  void dispose() {
    sync.close();
    code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => busy = true);
    try {
      final result = await sync.start();
      if (mounted) {
        SoundScope.of(context)?.cue(SoundCue.open);
        setState(() {
          offered = result;
          status = 'Код действует 5 минут. Не передавай его посторонним.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      busy = true;
      status = 'Соединяю устройства…';
    });
    try {
      await sync.connect(code.text);
      if (mounted) {
        SoundScope.of(context)?.cue(SoundCue.success);
        setState(() => status = 'Готово! Можно продолжать обучение здесь.');
        widget.onSynced();
      }
    } catch (e) {
      if (mounted) {
        SoundScope.of(context)?.cue(SoundCue.error);
        setState(
          () => status =
              'Не удалось соединиться: $e\nПроверь, что оба устройства в одной Wi-Fi сети, код ещё действует и брандмауэр разрешает DevCat локальные подключения.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _Scanner()));
    if (result != null && mounted) {
      code.text = result;
      await _connect();
    }
  }

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Синхронизация рядом',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Компьютер и телефон — в одной Wi-Fi сети. На первом устройстве покажи QR-код, на втором отсканируй его. Прогресс, место в курсе и учебный код объединятся в обе стороны. Интернет и аккаунт не нужны.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : _start,
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Показать QR-код'),
            ),
            if (Platform.isAndroid)
              OutlinedButton.icon(
                onPressed: busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Сканировать'),
              ),
          ],
        ),
        if (offered != null) ...[
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: ColoredBox(
                color: Colors.white,
                child: QrImageView(
                  data: offered!,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: offered!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Код подключения скопирован.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Скопировать код'),
              ),
              TextButton(
                onPressed: () {
                  sync.close();
                  setState(() {
                    offered = null;
                    status = 'Подключение закрыто.';
                  });
                },
                child: const Text('Закрыть подключение'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: code,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Или вставь код с другого устройства',
            hintText: 'devcat1.…',
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : _connect,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded),
          label: const Text('Соединить и синхронизировать'),
        ),
        if (status.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 14), child: Text(status)),
        const SizedBox(height: 10),
        Text(
          'Передача зашифрована AES-256-GCM. Ключ находится только в QR-коде. Настройки и пароли не передаются. Для следующего переноса повтори подключение.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _Scanner extends StatefulWidget {
  const _Scanner();
  @override
  State<_Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<_Scanner> {
  bool done = false;
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Наведи камеру на QR-код DevCat')),
    body: MobileScanner(
      controller: controller,
      onDetect: (capture) {
        for (final b in capture.barcodes) {
          final value = b.rawValue;
          if (!done && value != null && value.startsWith('devcat1.')) {
            done = true;
            Navigator.pop(context, value);
            break;
          }
        }
      },
    ),
  );
}
