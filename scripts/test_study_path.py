import json
from pathlib import Path
import unittest

from study_path import build, focus, facts, PRIMER

ROOT = Path(__file__).resolve().parents[1]


class StudyPathContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assets = ROOT / 'apps/devcat_flutter/assets/content'
        cls.courses = json.loads((assets / 'courses.json').read_text()) + [
            json.loads((assets / 'git_course.json').read_text())]
        cls.lessons = {l['id']: l for c in cls.courses for l in c['lessons']}
        cls.catalog = build(cls.courses)

    def test_all_topics_have_three_real_interactive_rounds(self):
        topics = self.catalog['topics']
        self.assertEqual({t['id'] for t in topics}, set(self.lessons))
        self.assertEqual(len(topics), 516)
        identifiers = set()
        for topic in topics:
            self.assertEqual(len(topic['rounds']), 3)
            for round_ in topic['rounds']:
                assessed = [s for s in round_['steps'] if s['kind'] != 'learn']
                self.assertGreaterEqual(len(assessed), 2, topic['id'])
                for step in round_['steps']:
                    self.assertNotIn(step['id'], identifiers)
                    identifiers.add(step['id'])
                    if step['kind'] == 'choice':
                        self.assertEqual(step['options'].count(step['answer']), 1)
                        self.assertGreaterEqual(len(step['options']), 3)
                    if step['kind'] == 'order':
                        self.assertTrue(all(piece.strip() for piece in step['pieces']))
                        self.assertEqual(''.join(step['pieces']), step['example'])
                # Reviews must support recall without first revealing the word.
                self.assertTrue(any(s['kind'] in ('write', 'order', 'code') for s in assessed)
                                or round_['level'] == 0, topic['id'])

    def test_code_gaps_restore_the_exact_runtime_verified_program(self):
        for topic in self.catalog['topics']:
            lesson = self.lessons[topic['id']]
            coding = [s for s in topic['rounds'][2]['steps'] if s['kind'] == 'code']
            if lesson.get('runnableExample') or lesson.get('challenge'):
                self.assertEqual(len(coding), 1, topic['id'])
            for step in coding:
                if step['mode'] == 'example':
                    self.assertEqual(step['code'].replace('___', step['answer'], 1),
                                     lesson['runnableExample']['code'], topic['id'])
                else:
                    if lesson['challenge']['language'] == 'sql':
                        # SQL labs are compared with their reference query on
                        # two real fixture databases by LocalRunner._checkSql.
                        self.assertTrue(lesson['challenge']['solution'], topic['id'])
                    else:
                        self.assertTrue(lesson['challenge']['tests'], topic['id'])

    def test_language_scoped_facts_and_real_predicted_outputs(self):
        for topic in self.catalog['topics']:
            lesson = self.lessons[topic['id']]
            cases = (lesson.get('runnableExample') or lesson.get('challenge') or {}).get('tests', [])
            for round_ in topic['rounds']:
                for step in round_['steps']:
                    if step['id'].endswith('.output'):
                        self.assertTrue(any(c['input'] == step['input'] and c['expected'] == step['answer']
                                            for c in cases), step['id'])
                    if topic['course'] != 'sql' and step.get('answer') == 'индекс':
                        self.assertNotIn('индекс SQL', step.get('accepted', []))
                    if step.get('image'):
                        self.assertTrue((ROOT / 'apps/devcat_flutter/assets/content' / step['image']).is_file())
        html = next(t for t in self.catalog['topics'] if t['id'] == 'html.links')
        self.assertEqual(html['term'], 'href')
        text = json.dumps(html, ensure_ascii=False)
        self.assertNotIn('независимой копии', text)
        sql = next(t for t in self.catalog['topics'] if t['id'] == 'sql.indexes')
        self.assertEqual(sql['term'], 'индекс')
        self.assertNotIn('первая позиция имеет номер ноль', json.dumps(sql, ensure_ascii=False))

    def test_syntax_hints_respect_the_language_and_do_not_read_keywords_inside_strings(self):
        line, token, explanation = focus('const input = 5;\nconsole.log(input);', 'javascript')
        self.assertEqual(token, 'console.log')
        self.assertNotIn('Python', explanation)
        line, token, explanation = focus('const note = "return input";\nconsole.log(note);', 'javascript')
        self.assertEqual(token, 'console.log')
        self.assertIn('JavaScript', explanation)

    def test_vocabulary_distractors_never_require_future_chapters(self):
        by_id = {t['id']: t for t in self.catalog['topics']}
        for course in self.courses:
            introduced = list(PRIMER.get(course['id'], []))
            for index, lesson in enumerate(course['lessons']):
                introduced.extend(facts(course, lesson, index))
                allowed = {value for pair in introduced for value in pair}
                for round_ in by_id[lesson['id']]['rounds']:
                    for step in round_['steps']:
                        if step['kind'] == 'choice' and not step['id'].endswith('.output'):
                            self.assertTrue(set(step['options']) <= allowed, step['id'])
        first = next(t for t in self.catalog['topics'] if t['course'] == 'python')
        self.assertNotIn('контекстному менеджеру', json.dumps(first, ensure_ascii=False))


if __name__ == '__main__':
    unittest.main()
