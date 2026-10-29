import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/course.dart';
import '../core/store.dart';
import '../core/tutor.dart';
import '../core/sound.dart';
import 'widgets.dart';

class TutorPage extends StatefulWidget {
  final List<Course> courses;
  final AppStore store;
  final String? language, lessonId;
  const TutorPage({
    super.key,
    required this.courses,
    required this.store,
    this.language,
    this.lessonId,
  });
  @override
  State<TutorPage> createState() => _TutorPageState();
}

class _TutorPageState extends State<TutorPage> {
  final input = TextEditingController(), scroll = ScrollController();
  final messages = <Map<String, String>>[];
  late String language;
  late List<Course> courses;
  String? lessonId;
  @override
  void initState() {
    super.initState();
    courses = List.of(widget.courses);
    if (!courses.any((c) => c.id == 'git')) {
      rootBundle.loadString('assets/content/git_course.json').then((text) {
        if (mounted) setState(() => courses.add(Course(jsonDecode(text))));
      });
    }
    language = widget.language ?? widget.courses.first.id;
    lessonId = widget.lessonId;
    final saved = widget.store.progress.draftsFor('tutor.conversation');
    if (saved.isNotEmpty) {
      try {
        messages.addAll(
          (jsonDecode(saved.first['text']) as List).map(
            (m) => Map<String, String>.from(m),
          ),
        );
      } catch (_) {
        /* Old malformed conversation does not affect progress. */
      }
    }
  }

  Future<void> ask([String? suggestion]) async {
    final question = (suggestion ?? input.text).trim();
    if (question.isEmpty) return;
    final answer = CourseTutor(
      courses,
    ).explain(question, language: language, lessonId: lessonId);
    setState(() {
      messages.add({'role': 'Ты', 'text': question});
      messages.add({'role': 'Кот', 'text': answer.text});
      if (answer.found) lessonId = answer.lessonId;
      input.clear();
      if (messages.length > 24) messages.removeRange(0, messages.length - 24);
    });
    SoundScope.of(
      context,
    )?.speak(answer.found ? CatMood.explaining : CatMood.thinking);
    while (jsonEncode(messages).length > 180000 && messages.length > 2) {
      messages.removeRange(0, 2);
    }
    await widget.store.draft('tutor.conversation', jsonEncode(messages));
    if (mounted && scroll.hasClients) {
      await scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Разберём вместе')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const CatPortrait(size: 52, mood: CatMood.explaining),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: language,
                  items: courses
                      .map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    language = value!;
                    lessonId = null;
                  }),
                  decoration: const InputDecoration(
                    labelText: 'О чём спрашиваем',
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Офлайн-разбор по материалам курса. Свободная нейросетевая генерация не включена.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            itemCount: messages.isEmpty ? 1 : messages.length,
            itemBuilder: (_, i) => messages.isEmpty
                ? const Text(
                    'Можно не знать ни одного термина. Начни с «сначала», либо напиши: «что такое переменная?».',
                  )
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        '${messages[i]['role']}\n\n${messages[i]['text']}',
                      ),
                    ),
                  ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children:
                ['сначала', 'по строкам', 'пример', 'ошибка', 'как проверить']
                    .map(
                      (q) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(q),
                          onPressed: () => ask(q),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => ask(),
                    decoration: const InputDecoration(
                      labelText: 'Что осталось непонятным?',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => ask(),
                  tooltip: 'Спросить кота',
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
