import hashlib
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]

class RebuiltNotebookTest(unittest.TestCase):
    def test_every_old_lecture_is_replaced_and_has_a_real_source(self):
        courses=json.loads((ROOT/'apps/devcat_flutter/assets/content/courses.json').read_text())
        baseline=json.loads((ROOT/'content/compatibility/v0.4.0-theory-sha256.json').read_text())
        actual={l['id']:l for c in courses for l in c['lessons']}
        self.assertEqual(set(actual),set(baseline))
        for ident,lesson in actual.items():
            self.assertNotEqual(hashlib.sha256(lesson['theory'].encode()).hexdigest(),baseline[ident],ident)
            self.assertGreaterEqual(lesson['questionRevision'],5)
            self.assertEqual(len(lesson['learning']['steps']),4)
            self.assertTrue(all(r['url'].startswith('https://') for r in lesson['learning']['references']))
        sources=json.loads((ROOT/'content/reference_sources.json').read_text())
        self.assertEqual(set(sources),{c['id'] for c in courses})
        for records in sources.values():
            self.assertEqual(len(records[0]['sha256']),64)

    def test_first_thirty_two_programming_lessons_have_complete_examples(self):
        courses=json.loads((ROOT/'apps/devcat_flutter/assets/content/courses.json').read_text())
        for course in courses:
            if course['id'] in ('html','css','sql'):continue
            for lesson in course['lessons'][:32]:
                self.assertTrue(lesson['learning']['codeIsComplete'],lesson['id'])
                self.assertTrue(lesson.get('runnableExample') or lesson.get('challenge'),lesson['id'])

if __name__=='__main__':unittest.main()
