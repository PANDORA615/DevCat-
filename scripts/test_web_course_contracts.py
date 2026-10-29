"""Prevent teaching CSS rules that have no target in their own HTML example."""
import json,re,unittest
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class Elements(HTMLParser):
 def __init__(self):super().__init__();self.classes=set();self.tags=set()
 def handle_starttag(self,tag,attrs):
  self.tags.add(tag)
  for name,value in attrs:
   if name=='class':self.classes.update((value or '').split())
class WebCourseContracts(unittest.TestCase):
 def test_each_css_selector_has_a_target_in_its_teaching_example(self):
  courses=json.loads((ROOT/'apps/devcat_flutter/assets/content/courses.json').read_text())
  for course in courses:
   if course['id']!='css':continue
   for lesson in course['lessons']:
    files=lesson['webExample'];parser=Elements();parser.feed(files['index.html'])
    selectors=set(re.findall(r'\.([a-z][a-z0-9-]*)',files['style.css']))
    self.assertTrue(selectors <= parser.classes,(lesson['id'],selectors-parser.classes))
    if lesson['id']=='css.forms':self.assertIn('input',parser.tags)
    if lesson['id']=='css.overflow':self.assertIn('img',parser.tags);self.assertIn('pre',parser.tags)
 def test_metadata_is_in_head_and_image_matches_the_ide_asset(self):
  courses=json.loads((ROOT/'apps/devcat_flutter/assets/content/courses.json').read_text())
  html=next(c for c in courses if c['id']=='html')
  document=next(l for l in html['lessons'] if l['id']=='html.metadata')['webExample']['index.html']
  self.assertLess(document.index('name="description"'),document.index('</head>'))
  self.assertEqual(document.count('name="viewport"'),1)
  source=(ROOT/'apps/devcat_flutter/lib/core/web_sample_assets.dart').read_text()
  literal=re.search(r'const webSampleCat\s*=\s*(.*);',source,re.S)[1]
  svg=json.loads(literal)
  for course in courses:
   if course['id'] in ['html','css']:
    for lesson in course['lessons']:self.assertEqual(lesson['webExample']['cat.svg'],svg)
if __name__=='__main__':unittest.main()
