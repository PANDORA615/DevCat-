import 'package:flutter/material.dart';
import '../core/course.dart';
import '../core/store.dart';

/// A course map, with reading and automatic task results kept explicit.
class CourseRouteSheet extends StatefulWidget {
  final Course course;
  final AppStore store;
  final int current;
  const CourseRouteSheet({
    super.key,
    required this.course,
    required this.store,
    required this.current,
  });
  @override
  State<CourseRouteSheet> createState() => _CourseRouteSheetState();
}

class _CourseRouteSheetState extends State<CourseRouteSheet> {
  String query = '';
  bool read(Lesson lesson) => widget.store.progress
      .draftsFor('learned.${lesson.id}')
      .any((d) => d['text'] == 'read');
  @override
  Widget build(BuildContext context) {
    final lessons = widget.course.lessons;
    final chapters = <String, List<int>>{};
    for (var i = 0; i < lessons.length; i++) {
      final lesson = lessons[i];
      if (query.isNotEmpty &&
          !'${lesson.title} ${lesson.chapter}'.toLowerCase().contains(query)) {
        continue;
      }
      chapters.putIfAbsent(lesson.chapter, () => []).add(i);
    }
    final count = lessons.where(read).length;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .86,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Учебный маршрут · ${widget.course.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Объяснение → пример → небольшой опыт → задача. Прочитано $count из ${lessons.length}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Найти тему',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (text) =>
                    setState(() => query = text.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    if (chapters.isEmpty)
                      const ListTile(
                        title: Text('Тема не найдена. Попробуй другое слово.'),
                      ),
                    for (final entry in chapters.entries)
                      ExpansionTile(
                        key: ValueKey('${entry.key}:$query'),
                        initiallyExpanded:
                            query.isNotEmpty ||
                            entry.value.contains(widget.current),
                        title: Text(entry.key),
                        subtitle: Text(
                          '${entry.value.length} занятий · ${entry.value.where((i) => read(lessons[i])).length} прочитано',
                        ),
                        children: [
                          for (final i in entry.value)
                            ListTile(
                              selected: i == widget.current,
                              leading: CircleAvatar(child: Text('${i + 1}')),
                              title: Text(lessons[i].title),
                              subtitle: Text(lessons[i].assessmentLabel),
                              trailing: Icon(
                                widget.store.progress.solved.contains(
                                      lessons[i].id,
                                    )
                                    ? Icons.verified_rounded
                                    : read(lessons[i])
                                    ? Icons.bookmark_added_outlined
                                    : Icons.chevron_right_rounded,
                              ),
                              onTap: () => Navigator.pop(context, i),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const Text(
                'Закладка — прочитано. Значок проверки — задача прошла автотесты.',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
