"""Assemble verified native artifacts and signed Android bytes inside GitHub Actions.

Only public application binaries are transferred via temporary, unreferenced Git blobs.
No signing key or password is accepted by this publisher.
"""
import base64
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

manifest = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
repository = os.environ['GITHUB_REPOSITORY']
token = os.environ['GH_TOKEN']


def api(path):
    request = urllib.request.Request(
        f'https://api.github.com/repos/{repository}/{path}',
        headers={'Authorization': f'Bearer {token}',
                 'Accept': 'application/vnd.github+json',
                 'X-GitHub-Api-Version': '2022-11-28'})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


assert manifest['version'] == 1
assert re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', manifest['tag'])
version = manifest['tag'][1:]
assert isinstance(manifest['build_run'], int) and manifest['build_run'] > 0
run = api(f"actions/runs/{manifest['build_run']}")
assert run['conclusion'] == 'success' and run['head_sha'] == manifest['build_commit']
subprocess.run(['git', 'diff', '--exit-code', manifest['build_commit'], 'HEAD', '--',
                'apps/devcat_flutter', 'content'], check=True)
expected_android = {f'DevCat-{version}-android-{abi}.apk' for abi in
                    ['universal', 'arm64-v8a', 'armeabi-v7a', 'x86_64']}
expected_android.add(f'DevCat-{version}-android.aab')
assert {item['name'] for item in manifest['files']} == expected_android
for item in manifest['files']:
    assert Path(item['name']).name == item['name']
    destination = output / item['name']
    digest = hashlib.sha256()
    size = 0
    with destination.open('wb') as target:
        for chunk in item['chunks']:
            blob = api(f"git/blobs/{chunk['sha']}")
            assert blob['encoding'] == 'base64'
            data = base64.b64decode(blob['content'])
            assert len(data) == chunk['size']
            assert hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == chunk['sha']
            target.write(data)
            digest.update(data)
            size += len(data)
    assert size == item['size'] and digest.hexdigest() == item['sha256']
    print(f"Reconstructed and verified {item['name']}", flush=True)

for source, name in [
    ('docs/SBOM.spdx.json', f'DevCat-{version}-SBOM.spdx.json'),
    ('docs/THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_NOTICES.md'),
    ('docs/android-release-cert.pem', 'DevCat-Android-release-cert.pem'),
    ('LICENSE', 'LICENSE'),
    (f'docs/releases/v{version}-SHA256SUMS', 'SHA256SUMS'),
]:
    shutil.copyfile(source, output / name)
expected = {'SHA256SUMS'}
for line in (output / 'SHA256SUMS').read_text().splitlines():
    checksum, name = line.split('  ', 1)
    assert Path(name).name == name
    assert hashlib.sha256((output / name).read_bytes()).hexdigest() == checksum, name
    expected.add(name)
assert expected == {path.name for path in output.iterdir()}
assert len(expected) == 20
print('All 20 public release assets match the reviewed checksum record.', flush=True)
