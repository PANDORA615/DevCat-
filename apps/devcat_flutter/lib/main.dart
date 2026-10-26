import 'dart:convert';
import 'dart:io';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/course.dart';
import 'core/sound.dart';
import 'core/store.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final override = Platform.environment['DEVCAT_DATA_DIR'];
  final directory = override == null
      ? await getApplicationSupportDirectory()
      : Directory(override);
  final store = AppStore(directory);
  await store.load();
  final courses =
      (jsonDecode(await rootBundle.loadString('assets/content/courses.json'))
              as List)
          .map((j) => Course(j))
          .toList();
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1240, 840),
        minimumSize: Size(640, 560),
        center: true,
        title: 'DevCat',
        backgroundColor: Colors.transparent,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  runApp(DevCatApp(store: store, courses: courses));
}

class DevCatApp extends StatefulWidget {
  final AppStore store;
  final List<Course> courses;
  const DevCatApp({super.key, required this.store, required this.courses});
  @override
  State<DevCatApp> createState() => _DevCatAppState();
}

class _DevCatAppState extends State<DevCatApp> {
  final sounds = SoftSounds();
  @override
  void dispose() {
    sounds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      sounds.enabled = store.setting('sound', true);
      sounds.volume = store.setting<num>('volume', .22).toDouble();
      final seed = Color(store.setting('seedColor', 0xff416c57));
      return DynamicColorBuilder(
        builder: (light, dark) {
          ThemeData theme(Brightness brightness) {
            final dynamic = store.setting('dynamicColor', false)
                ? (brightness == Brightness.light ? light : dark)
                : null;
            final scheme =
                dynamic ??
                ColorScheme.fromSeed(
                  seedColor: seed,
                  brightness: brightness,
                  contrastLevel: store.setting('highContrast', false) ? .8 : 0,
                );
            return ThemeData(
              useMaterial3: true,
              colorScheme: scheme,
              scaffoldBackgroundColor: scheme.surface,
              fontFamily: Platform.isLinux ? 'DejaVu Sans' : null,
              cardTheme: CardThemeData(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                ),
              ),
              navigationBarTheme: const NavigationBarThemeData(height: 76),
              tooltipTheme: const TooltipThemeData(
                waitDuration: Duration(milliseconds: 500),
              ),
              visualDensity: VisualDensity.standard,
            );
          }

          return MaterialApp(
            title: 'DevCat',
            debugShowCheckedModeBanner: false,
            locale: const Locale('ru'),
            supportedLocales: const [Locale('ru'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme(Brightness.light),
            darkTheme: theme(Brightness.dark),
            themeMode: switch (store.setting('theme', 'system')) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            themeAnimationDuration: Duration(
              milliseconds: store.setting('reducedMotion', false) ? 0 : 280,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations:
                    store.setting('reducedMotion', false) ||
                    MediaQuery.of(context).disableAnimations,
              ),
              child: Listener(onPointerUp: (_) => sounds.tap(), child: child!),
            ),
            home: DevCatShell(
              store: store,
              courses: widget.courses,
              sounds: sounds,
            ),
          );
        },
      );
    },
  );
}
