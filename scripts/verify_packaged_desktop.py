"""Exercise the installed app's own runtime lookup, not Flutter's test process."""
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
target = sys.argv[1]
executable = repo / {
    'windows': 'apps/devcat_flutter/build/windows/x64/runner/Release/devcat.exe',
    'linux': 'apps/devcat_flutter/build/linux/x64/release/bundle/devcat',
    'macos': 'apps/devcat_flutter/build/macos/Build/Products/Release/DevCat.app/Contents/MacOS/DevCat',
}[target]
report = repo / f'build/packaged-runtime-{target}.json'
environment = os.environ.copy()
environment.pop('DEVCAT_RUNTIME_DIR', None)
environment['DEVCAT_REQUIRE_BUNDLED'] = 'true'
environment['DEVCAT_ISOLATE_TOOLS'] = 'true'
environment['DEVCAT_VERIFY_RUNTIMES_REPORT'] = str(report)
command = [str(executable)]
if target == 'linux':
    command = ['xvfb-run', '-a', *command]
result = subprocess.run(command, env=environment, timeout=600)
assert result.returncode == 0, f'Packaged app failed: {result.returncode}'
data = json.loads(report.read_text())
assert data['passed'], data
assert set(data['languages']) == {'c', 'cpp', 'csharp', 'python', 'java', 'javascript', 'go', 'sql'}
print(json.dumps(data, indent=2, ensure_ascii=False))
