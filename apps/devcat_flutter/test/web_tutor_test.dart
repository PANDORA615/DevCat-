import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/project.dart';
import 'package:devcat/core/tutor.dart';
import 'package:devcat/core/web_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Browser preview serves only project files over a tokenized loopback address',
    () async {
      final project = DevProject.create('css', 'First page');
      final preview = WebPreview();
      final client = HttpClient();
      try {
        final uri = await preview.open(project);
        expect(uri.host, '127.0.0.1');
        final response = await (await client.getUrl(uri)).close();
        expect(response.statusCode, 200);
        expect(
          await utf8.decoder.bind(response).join(),
          contains('Моя первая страница'),
        );
        project.files['style.css'] = 'body { color: green; }';
        final css = await (await client.getUrl(
          uri.resolve('style.css'),
        )).close();
        expect(css.headers.contentType!.mimeType, 'text/css');
        expect(await utf8.decoder.bind(css).join(), contains('green'));
        final wrong = await (await client.getUrl(
          uri.replace(path: '/wrong/index.html'),
        )).close();
        expect(wrong.statusCode, 404);
        await wrong.drain<void>();
        final missing = await (await client.getUrl(
          uri.resolve('../README.md'),
        )).close();
        expect(missing.statusCode, 404);
        await missing.drain<void>();
        project.files['pages/index.html'] = '<img src="cat.svg">';
        project.files['pages/cat.svg'] =
            '<svg xmlns="http://www.w3.org/2000/svg"/>';
        project.entry = 'pages/index.html';
        final nested = await preview.open(project);
        expect(nested.pathSegments.last, 'index.html');
        final image = await (await client.getUrl(
          nested.resolve('cat.svg'),
        )).close();
        expect(image.statusCode, 200);
        expect(image.headers.contentType!.mimeType, 'image/svg+xml');
        await image.drain<void>();
      } finally {
        client.close(force: true);
        await preview.close();
      }
    },
  );
  test(
    'Course tutor keeps follow-up context and refuses unsupported questions',
    () {
      final courses =
          (jsonDecode(File('assets/content/courses.json').readAsStringSync())
                  as List)
              .map((c) => Course(c))
              .toList();
      final tutor = CourseTutor(courses);
      final first = tutor.explain('что такое переменная', language: 'go');
      expect(first.found, isTrue);
      expect(first.text, contains('присваива'));
      final next = tutor.explain(
        'по строкам',
        language: 'go',
        lessonId: 'go.zero.variable',
      );
      expect(next.lessonId, 'go.zero.variable');
      expect(next.text, contains('balance'));
      expect(
        tutor.explain('космические пингвины на Юпитере', language: 'css').found,
        isFalse,
      );
      expect(tutor.explain('сначала', language: 'html').found, isTrue);
      expect(tutor.explain('height', language: 'css').found, isTrue);
    },
  );
}
