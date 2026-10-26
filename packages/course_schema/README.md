# Content schema v1

Course: id, name, version, subtitle, source, revision, review_status, last_verified, author, lessons[].
Lesson: id, title, kind, theory, examples[2+], mistakes[2+].
Runtime model: `apps/devcat_flutter/lib/core/course.dart`. Source of authored content: `scripts/write_content.py`; generated `content/*/intro.json` and bundled `assets/content/courses.json` must match (CI checks diff).

Exercises: seed + language + template kind → statement/starter/reference/three hints/test cases. Explicitly bounded introductory coverage; no claim of full knowledge or editorial expert review.
