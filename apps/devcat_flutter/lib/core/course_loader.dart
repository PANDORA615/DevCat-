import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'course.dart';

/// Decode the large lecture corpus away from the UI; create its practice banks
/// in the application isolate, where the IDE and generator actually use them.
Future<List<Course>> loadCourses(AssetBundle bundle) async {
  final text = await bundle.loadString('assets/content/courses.json');
  final rows = await Isolate.run(() => jsonDecode(text) as List);
  return rows.map((row) => Course(row)).toList();
}
