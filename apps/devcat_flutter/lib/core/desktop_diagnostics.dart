import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'course.dart';
import 'desktop_runtime.dart';
import 'runner.dart';

/// CI checks the actual packaged executable, before opening a learning window.
Future<bool> verifyPackagedDesktop(String reportPath) async {
  final report = <String, dynamic>{
    'schema': 1,
    'passed': false,
    'languages': <String, dynamic>{},
  };
  try {
    final root = DesktopRuntime.root;
    if (root == null) throw StateError('Packaged toolchains are missing');
    report['runtimeRoot'] = root;
    final courses =
        (jsonDecode(await rootBundle.loadString('assets/content/courses.json'))
                as List)
            .map((data) => Course(data))
            .toList();
    for (final language in executableLanguages) {
      final lesson = courses.firstWhere((c) => c.id == language).lessons.first;
      final example = lesson.runnableExample!;
      final sample = (example['tests'] as List).first;
      final result = await LocalRunner().run(
        language,
        example['code'],
        sample['input'],
      );
      final output = language == 'sql'
          ? result.output.split('\n').skip(1).join('\n')
          : result.output;
      final passed =
          result.ok &&
          LocalRunner.normalize(output) ==
              LocalRunner.normalize(sample['expected']);
      (report['languages'] as Map)[language] = {
        'passed': passed,
        'error': result.error,
      };
      if (!passed) throw StateError('$language failed: ${result.error}');
    }
    report['passed'] = true;
  } catch (error) {
    report['error'] = error.toString();
  }
  await File(reportPath).writeAsString(jsonEncode(report));
  return report['passed'] == true;
}
