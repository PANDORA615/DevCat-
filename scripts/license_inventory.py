"""Record dependency versions and preserve actual installed license texts."""
import json, re, hashlib
from pathlib import Path
from urllib.parse import urlparse,unquote
root=Path(__file__).resolve().parents[1]
app=root/'apps/devcat_flutter'
config=json.loads((app/'.dart_tool/package_config.json').read_text())
lock=(app/'pubspec.lock').read_text()
versions={m[0]:m[1] for m in re.findall(r'^  ([a-zA-Z_0-9]+):\n(?:(?:    .*|      .*)\n)*?    version: "([^"]+)"',lock,re.M)}
notices=['# Third-party license notices\n\nActual LICENSE files from the locked Flutter/Dart dependencies. Desktop toolchains are supplied by the user. Android runtimes are bundled; their original license texts follow the Flutter/Dart notices.\n']
packages=[]
for pkg in config['packages']:
 if pkg['name']=='devcat':continue
 uri=urlparse(pkg['rootUri'])
 path=Path(unquote(uri.path)) if uri.scheme=='file' else (app/'.dart_tool'/pkg['rootUri']).resolve()
 license=next((p for n in ['LICENSE','LICENSE.md','LICENSE.txt'] if (p:=path/n).is_file()),None)
 text=license.read_text(errors='replace') if license else 'License file not present at package root. Consult upstream distribution.'
 notices.append(f"\n## {pkg['name']} {versions.get(pkg['name'],'Flutter SDK')}\n\n```text\n{text}\n```\n")
 packages.append({'SPDXID':"SPDXRef-"+pkg["name"].replace("_","-"),'name':pkg['name'],'versionInfo':versions.get(pkg['name'],'Flutter-3.47.8'),'downloadLocation':f"https://pub.dev/packages/{pkg['name']}" if pkg['name'] in versions else 'https://github.com/flutter/flutter/tree/3.47.8','filesAnalyzed':False,'licenseConcluded':'NOASSERTION','licenseDeclared':'NOASSERTION','copyrightText':'NOASSERTION'})
for font in ['Nunito', 'JetBrainsMono']:
 text=(app/'assets/fonts'/f'{font}-OFL.txt').read_text()
 notices.append(f'\n## {font} font — SIL Open Font License\n\n```text\n{text}\n```\n')
notices.append('\n' + (root/'docs/ANDROID_RUNTIME_NOTICES.md').read_text())
(root/'docs/THIRD_PARTY_NOTICES.md').write_text(''.join(notices))
(root/'docs/SBOM.spdx.json').write_text(json.dumps({'spdxVersion':'SPDX-2.3','dataLicense':'CC0-1.0','SPDXID':'SPDXRef-DOCUMENT','name':'DevCat-0.6.0','documentNamespace':'https://github.com/PANDORA615/DevCat-/sbom/0.6.0','creationInfo':{'creators':['Tool: DevCat license_inventory.py'],'created':'2026-10-30T00:00:00Z'},'packages':packages},indent=2)+'\n')
