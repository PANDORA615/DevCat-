import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/course.dart';
import 'core/sound.dart';
import 'core/mascot.dart';
import 'core/study.dart';
import 'core/store.dart';
import 'core/desktop_diagnostics.dart';
import 'core/content_runtime.dart';
import 'core/desktop_updates.dart';
import 'core/learning_assets.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final diagnosticReport =
      Platform.environment['DEVCAT_VERIFY_RUNTIMES_REPORT'];
  if (diagnosticReport != null && !Platform.isAndroid) {
    exit(await verifyPackagedDesktop(diagnosticReport) ? 0 : 1);
  }
  LicenseRegistry.addLicense(() async* {
    for (final name in ['Nunito', 'JetBrainsMono']) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$name-OFL.txt'));
    }
  });
  if (Platform.isAndroid) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        ['Встроенные среды исполнения Android'],
        await rootBundle.loadString(
          'assets/content/android-runtime-notices.txt',
        ),
      );
    });
  }
  final override = Platform.environment['DEVCAT_DATA_DIR'];
  final directory = override == null
      ? await getApplicationSupportDirectory()
      : Directory(override);
  final store = AppStore(directory);
  await store.load();
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
  runApp(_LearningBoot(store: store));
}

class _LearningBoot extends StatefulWidget {
  final AppStore store;
  const _LearningBoot({required this.store});
  @override
  State<_LearningBoot> createState() => _LearningBootState();
}

class _LearningBootState extends State<_LearningBoot> {
  late final Future<List<Course>> loading = _load();
  Future<List<Course>> _load() async {
    await ContentRuntime.initialize(widget.store.directory);
    final data =
        jsonDecode(
              await LearningAssets.bundle.loadString(
                'assets/content/courses.json',
              ),
            )
            as List;
    return data.map((j) => Course(j)).toList();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Course>>(
    future: loading,
    builder: (_, snapshot) {
      if (snapshot.hasData) {
        return DefaultAssetBundle(
          bundle: LearningAssets.bundle,
          child: DevCatApp(store: widget.store, courses: snapshot.data!),
        );
      }
      final seed = Color(widget.store.setting('seedColor', 0xff416c57));
      return MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
          fontFamily: 'Nunito',
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: seed,
            brightness: Brightness.dark,
          ),
          fontFamily: 'Nunito',
        ),
        themeMode: switch (widget.store.setting('theme', 'system')) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/devcat_book.png',
                    width: 120,
                    height: 110,
                  ),
                  const SizedBox(height: 24),
                  if (!snapshot.hasError)
                    const SizedBox(
                      width: 180,
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    snapshot.hasError
                        ? 'Не удалось открыть встроенные уроки. Переустанови DevCat. Прогресс хранится отдельно.'
                        : 'Готовлю твою мастерскую…',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
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
  Timer? updateChecks;
  DesktopUpdates? updates;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final runtime = ContentRuntime.current;
      if (runtime == null) return;
      updates = DesktopUpdates.current = DesktopUpdates(runtime);
      void check() {
        if (mounted && widget.store.setting('autoCheckUpdates', true)) {
          unawaited(
            updates!.check(
              beta: widget.store.setting('updateChannel', 'beta') == 'beta',
              automatic: true,
            ),
          );
        }
      }

      check();
      updateChecks = Timer.periodic(const Duration(hours: 6), (_) => check());
    });
  }

  @override
  void dispose() {
    updateChecks?.cancel();
    updates?.dispose();
    if (identical(DesktopUpdates.current, updates)) {
      DesktopUpdates.current = null;
    }
    sounds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      if ((!store.setting('sound', true) && sounds.enabled) ||
          (!store.setting('catVoice', true) && sounds.voiceEnabled)) {
        sounds.stopVoice();
      }
      sounds.enabled = store.setting('sound', true);
      sounds.volume = store.setting<num>('volume', .15).toDouble();
      sounds.voiceEnabled = store.setting('catVoice', true);
      sounds.voiceVolume = store.setting<num>('voiceVolume', .20).toDouble();
      sounds.voiceStyle = store.setting('voiceStyle', 'auto');
      sounds.achievementVolume = store
          .setting<num>('achievementVolume', .15)
          .toDouble();
      final selectedAppearance = store.setting('mascotAppearance', 'classic');
      final appearance = selectedAppearance == 'auto'
          ? MascotCatalog.evolution(1 + StudyLedger(store.progress).xp ~/ 200)
          : selectedAppearance;
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
              fontFamily: store.setting('uiFont', 'Nunito'),
              textTheme: ThemeData(brightness: brightness).textTheme
                  .apply(
                    fontFamily: store.setting('uiFont', 'Nunito'),
                    fontSizeFactor: store
                        .setting<num>('uiScale', 1.0)
                        .toDouble(),
                  )
                  .copyWith(
                    bodyMedium: TextStyle(
                      fontFamily: store.setting('uiFont', 'Nunito'),
                      fontSize:
                          14 * store.setting<num>('uiScale', 1.0).toDouble(),
                      fontWeight: FontWeight.w600,
                      height: 1.6,
                    ),
                    bodyLarge: TextStyle(
                      fontFamily: store.setting('uiFont', 'Nunito'),
                      fontSize:
                          16 * store.setting<num>('uiScale', 1.0).toDouble(),
                      fontWeight: FontWeight.w600,
                      height: 1.6,
                    ),
                  ),
              cardTheme: CardThemeData(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    store.setting<num>('cornerRadius', 28).toDouble(),
                  ),
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
              child: SoundScope(
                sounds: sounds,
                child: MascotScope(
                  appearance: appearance,
                  child: PointerSoundLayer(sounds: sounds, child: child!),
                ),
              ),
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
