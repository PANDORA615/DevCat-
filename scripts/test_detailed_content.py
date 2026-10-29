import hashlib
import json
from pathlib import Path
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[1]

class DetailedContentTest(unittest.TestCase):
    def test_progress_and_existing_challenge_contracts_are_preserved(self):
        old=json.loads((ROOT/'content/compatibility/v0.2.1-contracts.json').read_text())
        courses=json.loads((ROOT/'apps/devcat_flutter/assets/content/courses.json').read_text())
        current={}
        for course in courses:
            if course['id'] in old['courses']:
                self.assertEqual([l['id'] for l in course['lessons'][8:48]],old['courses'][course['id']])
                self.assertEqual(len(course['lessons']),56)
            else:self.assertEqual(len(course['lessons']),24)
            for lesson in course['lessons']:
                if lesson['id'] in old['questions'] and lesson['questions'] != old['questions'][lesson['id']]:
                    self.assertGreater(lesson.get('questionRevision',1),1)
                self.assertEqual(len(lesson['questions']),len(lesson['answers']))
                self.assertTrue(all(a.strip() for a in lesson['answers']))
                for section in lesson['sections']:
                    if 'table' in section:
                        self.assertTrue(all(len(row)==len(section['table']['columns']) for row in section['table']['rows']))
                if lesson['challenge']:
                    task=lesson['challenge'];current[task['id']]=hashlib.sha256(json.dumps(task,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
        self.assertEqual(current,old['challenges'])

    def test_all_eight_offline_books_and_licenses_are_in_export(self):
        with zipfile.ZipFile(ROOT/'docs/DevCat-lectures.zip') as archive:
            self.assertIsNone(archive.testzip())
            names=archive.namelist()
            self.assertEqual(len([n for n in names if n.endswith('.html')]),12)
            self.assertEqual(len([n for n in names if n.endswith('.md')]),11)
            for language in ['c','cpp','csharp','python','java','javascript','go','sql']:
                html=archive.read(language+'.html').decode()
                self.assertEqual(html.count('<section aria-labelledby='),56)
                self.assertIn('id="lesson-48"',html)
                self.assertIn('<details>',html)
                self.assertNotIn('<script',html)
                self.assertNotIn('src="https:',html)
            for name in ['Nunito-OFL.txt','JetBrainsMono-OFL.txt','memory.png','data.png','debug.png','workbench.png']:
                self.assertIn('assets/'+name,names)

if __name__=='__main__':unittest.main()
