import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Portable toolchains installed alongside the app. No downloads or PATH edits.
class DesktopRuntime {
  static String? get root {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return null;
    }
    final override = Platform.environment['DEVCAT_RUNTIME_DIR'];
    final base =
        override ??
        (Platform.isMacOS
            ? p.join(
                p.dirname(Platform.resolvedExecutable),
                '..',
                'Resources',
                'runtime',
              )
            : p.join(p.dirname(Platform.resolvedExecutable), 'runtime'));
    if (!File(p.join(base, 'manifest.json')).existsSync()) {
      if (const bool.fromEnvironment('DEVCAT_BUNDLED_DESKTOP') ||
          override != null ||
          Platform.environment['DEVCAT_REQUIRE_BUNDLED'] == 'true') {
        throw const FileSystemException(
          'Встроенные среды отсутствуют. Переустанови полную версию DevCat.',
        );
      }
      return null; // Development builds may use the developer's tools.
    }
    final manifest = jsonDecode(
      File(p.join(base, 'manifest.json')).readAsStringSync(),
    );
    if (manifest['schema'] != 1) {
      throw const FormatException('Неверная версия встроенных сред.');
    }
    final id = Platform.isWindows
        ? 'windows-x64'
        : Platform.isLinux
        ? 'linux-x64'
        : Abi.current() == Abi.macosArm64
        ? 'macos-arm64'
        : 'macos-x64';
    if (!(manifest['platforms'] as List).contains(id)) {
      throw FileSystemException('В установщике нет среды для $id.');
    }
    return p.normalize(p.join(base, id));
  }

  static String tool(String root, String component, String executable) =>
      p.join(root, component, executable);

  static ({
    String executable,
    List<String> args,
    Map<String, String> environment,
  })
  command(String executable, List<String> args, {required String cwd}) {
    final base = root;
    if (base == null) {
      return (executable: executable, args: args, environment: const {});
    }
    final windows = Platform.isWindows;
    final name = p.basenameWithoutExtension(executable);
    final suffix = windows ? '.exe' : '';
    final java = p.join(base, 'java');
    final python = p.join(base, 'python');
    final dotnet = p.join(base, 'dotnet');
    final paths = [
      p.dirname(Platform.resolvedExecutable),
      p.join(base, 'zig'),
      p.join(base, 'go', 'bin'),
      p.join(java, 'bin'),
      dotnet,
      windows ? python : p.join(python, 'bin'),
      p.join(base, 'node', windows ? '' : 'bin'),
    ];
    final cache = p.join(Directory.systemTemp.path, 'devcat-tool-cache');
    Directory(cache).createSync(recursive: true);
    final env = <String, String>{
      'PATH': [
        ...paths,
        Platform.environment['PATH'] ?? '',
      ].join(windows ? ';' : ':'),
      'JAVA_HOME': java,
      'DOTNET_ROOT': dotnet,
      'DOTNET_MULTILEVEL_LOOKUP': '0',
      'DOTNET_CLI_TELEMETRY_OPTOUT': '1',
      'DOTNET_SKIP_FIRST_TIME_EXPERIENCE': '1',
      'DOTNET_NOLOGO': '1',
      'DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE': 'true',
      'GOROOT': p.join(base, 'go'),
      'GOTOOLCHAIN': 'local',
      'GOPROXY': 'off',
      'GOSUMDB': 'off',
      'GOTELEMETRY': 'off',
      'CGO_ENABLED': '0',
      'GOCACHE': p.join(cache, 'go'),
      'PYTHONHOME': python,
      'PYTHONNOUSERSITE': '1',
      'PYTHONUTF8': '1',
      'PYTHONIOENCODING': 'utf-8',
      'ZIG_GLOBAL_CACHE_DIR': p.join(cache, 'zig'),
      'MSBUILDDISABLENODEREUSE': '1',
      'DOTNET_CLI_USE_MSBUILD_SERVER': '0',
    };
    if (Platform.isLinux && Directory(p.join(base, 'native')).existsSync()) {
      env['LD_LIBRARY_PATH'] = [
        p.join(base, 'native'),
        Platform.environment['LD_LIBRARY_PATH'] ?? '',
      ].join(':');
      env['DOTNET_ICU_VERSION_OVERRIDE'] = File(
        p.join(base, 'native', 'icu-version.txt'),
      ).readAsStringSync().trim();
    }
    if (Platform.environment['DEVCAT_ISOLATE_TOOLS'] == 'true') {
      env['PATH'] = [
        ...paths,
        windows
            ? p.join(Platform.environment['SystemRoot']!, 'System32')
            : '/usr/bin:/bin',
      ].join(windows ? ';' : ':');
      for (final key in [
        'CPATH',
        'CPLUS_INCLUDE_PATH',
        'LIBRARY_PATH',
        'INCLUDE',
        'LIB',
        'SDKROOT',
      ]) {
        env[key] = '';
      }
      if (Platform.isMacOS) env['DEVELOPER_DIR'] = '/devcat-no-system-sdk';
    }
    String? resolved;
    var arguments = args;
    switch (name) {
      case 'clang':
      case 'gcc':
      case 'clang++':
      case 'g++':
        resolved = p.join(base, 'zig', 'zig$suffix');
        arguments = [
          name.endsWith('++') ? 'c++' : 'cc',
          if (!args.contains('--version')) ...[
            '-target',
            windows
                ? 'x86_64-windows-gnu'
                : Platform.isLinux
                ? 'x86_64-linux-gnu.2.35'
                : Abi.current() == Abi.macosArm64
                ? 'aarch64-macos.12.0'
                : 'x86_64-macos.12.0',
          ],
          ...args,
        ];
      case 'dotnet':
        resolved = p.join(dotnet, 'dotnet$suffix');
      case 'go':
        resolved = p.join(base, 'go', 'bin', 'go$suffix');
      case 'java':
      case 'javac':
        resolved = p.join(java, 'bin', '$name$suffix');
      case 'python':
      case 'python3':
        resolved = windows
            ? p.join(python, 'python.exe')
            : p.join(python, 'bin', 'python3');
      case 'node':
        resolved = p.join(base, 'node', windows ? 'node.exe' : 'bin/node');
    }
    if (resolved != null && !File(resolved).existsSync()) {
      throw FileSystemException(
        'Повреждена встроенная среда $name. Переустанови DevCat.',
        resolved,
      );
    }
    return (
      executable: resolved ?? executable,
      args: arguments,
      environment: env,
    );
  }
}
