"""Attest final native package names, sizes and SHA after bundled-tool tests."""
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
target = sys.argv[1]
version = re.search(r'^version:\s*([^+\s]+)', (repo/'apps/devcat_flutter/pubspec.yaml').read_text(), re.M)[1]
files = sorted(p for p in (repo / 'dist').glob(f'DevCat-{version}-*') if p.is_file())
assert len(files) == (6 if target == 'linux' else 2), [p.name for p in files]
result = {'schema': 1, 'platform': target,
          'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
          'files': []}
runtime_report = json.loads((repo / f'build/packaged-runtime-{target}.json').read_text())
assert runtime_report['passed'] and len(runtime_report['languages']) == 8
result['packagedRuntimeCheck'] = runtime_report
for path in files:
    assert path.stat().st_size < 2 * 1024**3, 'Package exceeds GitHub per-file limit'
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    result['files'].append({'name': path.name, 'bytes': path.stat().st_size, 'sha256': digest})
(repo / f'build/desktop-proof-{target}.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
