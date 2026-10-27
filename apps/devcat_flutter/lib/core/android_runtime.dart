import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// All executable components come from this APK. The platform installer streams
/// the matching ABI's bundled image to private storage on first use.
class AndroidRuntime {
  static const channel = MethodChannel('dev.devcat/local-runtime');
  static Future<Map<String, String>>? _installation;

  static Future<Map<String, String>> ensureInstalled() {
    return _installation ??= _install();
  }

  static Future<Map<String, String>> _install() async {
    try {
      final data = await channel.invokeMapMethod<String, String>('prepare');
      if (data == null || data['root'] == null || data['nativeLib'] == null) {
        throw const FormatException('Неполный встроенный пакет исполнения.');
      }
      return data;
    } catch (_) {
      _installation = null;
      rethrow;
    }
  }

  static String guestPath(String argument, String cwd) {
    if (argument == cwd) return '/work';
    if (argument.startsWith('$cwd/')) {
      return '/work/${argument.substring(cwd.length + 1)}';
    }
    return argument;
  }

  static Future<Process> start(
    String executable,
    List<String> args, {
    required String cwd,
  }) async {
    final installed = await ensureInstalled();
    final native = installed['nativeLib']!;
    final temp = Directory(p.join(installed['root']!, 'tmp'));
    await temp.create(recursive: true);
    return Process.start(
      p.join(native, 'libdevcat_proot.so'),
      [
        '--kill-on-exit',
        '-0',
        '-r',
        installed['root']!,
        '-b',
        '/dev',
        '-b',
        '/proc',
        '-b',
        '$cwd:/work',
        '-w',
        '/work',
        '/usr/bin/env',
        '-i',
        'PATH=/opt/dotnet:/usr/local/go/bin:/usr/bin:/bin',
        'HOME=/root',
        'TMPDIR=/tmp',
        'LANG=C.UTF-8',
        'DOTNET_ROOT=/opt/dotnet',
        'DOTNET_CLI_TELEMETRY_OPTOUT=1',
        'DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1',
        'DOTNET_NOLOGO=1',
        'DOTNET_EnableDiagnostics=0',
        'GOTOOLCHAIN=local',
        'GOPROXY=off',
        'GOSUMDB=off',
        'GOCACHE=/tmp/go-build',
        guestPath(executable, cwd),
        ...args.map((arg) => guestPath(arg, cwd)),
      ],
      workingDirectory: cwd,
      environment: {
        'PROOT_LOADER': p.join(native, 'libdevcat_loader.so'),
        'PROOT_NO_SECCOMP': '1',
        'PROOT_TMP_DIR': temp.path,
      },
    );
  }
}
