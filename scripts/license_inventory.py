"""Record dependency versions and preserve actual installed license texts."""
import json, re, hashlib
from pathlib import Path
from urllib.parse import urlparse,unquote
root=Path(__file__).resolve().parents[1]
version=re.search(r'^version:\s*([^+\s]+)', (root/'apps/devcat_flutter/pubspec.yaml').read_text(),re.M)[1]
app=root/'apps/devcat_flutter'
config=json.loads((app/'.dart_tool/package_config.json').read_text())
lock=(app/'pubspec.lock').read_text()
versions={m[0]:m[1] for m in re.findall(r'^  ([a-zA-Z_0-9]+):\n(?:(?:    .*|      .*)\n)*?    version: "([^"]+)"',lock,re.M)}
notices=['# Third-party license notices\n\nActual LICENSE files from the locked Flutter/Dart dependencies. Desktop and Android toolchains are bundled; their original license texts follow the Flutter/Dart notices.\n']
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
desktop=json.loads((root/'scripts/desktop_runtime_versions.json').read_text())
notices.append('\n## Bundled desktop runtimes\n\nZig/Clang, CPython, .NET SDK, Liberica JDK, Node.js and Go are included in the desktop packages. Original upstream license and legal files remain under runtime/<platform>/<component>. Exact versions, archive URLs and checksums are recorded in scripts/desktop_runtime_versions.json and the installed runtime/manifest.json. Corresponding OpenJDK sources are included with the release.\n')
for platform, components in desktop['platforms'].items():
 for name, item in components.items():
  algorithm='sha512' if 'sha512' in item else 'sha256'
  packages.append({'SPDXID':f'SPDXRef-desktop-{platform}-{name}','name':f'{name}-{platform}','versionInfo':item['version'],'downloadLocation':item['url'],'checksums':[{'algorithm':algorithm.upper(),'checksumValue':item[algorithm]}],'filesAnalyzed':False,'licenseConcluded':'NOASSERTION','licenseDeclared':'NOASSERTION','copyrightText':'NOASSERTION'})
packages.append({'SPDXID': 'SPDXRef-windows-vc143-runtime', 'name': 'Microsoft Visual C++ 2022 app-local runtime (VC143)', 'downloadLocation': 'https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170', 'filesAnalyzed': False, 'licenseConcluded': 'NOASSERTION', 'licenseDeclared': 'NOASSERTION', 'copyrightText': 'Microsoft Corporation', 'comment': 'Windows app-local DLLs from the official Visual Studio 2022 VC/Redist/MSVC x64/Microsoft.VC143.CRT directory on the build runner. Original binaries and embedded copyright information are preserved.'})
notices.insert(1, "\n## Microsoft Visual C++ app-local runtime (Windows)\n\nWindows packages include the unmodified Microsoft.VC143.CRT x64 redistributable DLLs from the official Visual Studio 2022 installation. These Microsoft components retain their original embedded copyright and version information and are governed by Microsoft license terms, separately from DevCat's MIT license. Distribution reference and applicable license information: https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170 and https://visualstudio.microsoft.com/license-terms/.\n\n")
(root/'docs/THIRD_PARTY_NOTICES.md').write_text(''.join(notices))
(root/'docs/SBOM.spdx.json').write_text(json.dumps({'spdxVersion':'SPDX-2.3','dataLicense':'CC0-1.0','SPDXID':'SPDXRef-DOCUMENT','name':'DevCat-'+version,'documentNamespace':'https://github.com/PANDORA615/DevCat-/sbom/'+version,'creationInfo':{'creators':['Tool: DevCat license_inventory.py'],'created':'2026-11-04T00:00:00Z'},'packages':packages},indent=2)+'\n')
