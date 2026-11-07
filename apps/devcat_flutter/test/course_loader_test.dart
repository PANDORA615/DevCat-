import 'package:devcat/core/course.dart';
import 'package:devcat/core/course_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Background lecture loading keeps all languages and populates local exercise banks',
    () async {
      coursePracticeBank.clear();
      final courses = await loadCourses(rootBundle);
      expect(
        courses.map((course) => course.id).toSet(),
        languageNames.keys.toSet(),
      );
      for (final language in executableLanguages) {
        expect(coursePracticeBank[language], isNotEmpty, reason: language);
      }
      expect(
        courses.expand((course) => course.lessons).length,
        greaterThan(450),
      );
    },
  );
}
