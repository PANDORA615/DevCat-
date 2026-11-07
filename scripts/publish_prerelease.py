"""Publish reviewed CI outputs as a prerelease, with bounded staging and hashes.

No application binaries are rebuilt or signed here. The release remains a draft
until every asset is verified and uploaded. Requires gh and Python 3.12 on Actions.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile

REPO = 'PANDORA615/DevCat-'
LANGUAGES = {'c', 'cpp', 'csharp', 'python', 'java', 'javascript', 'go', 'sql'}


def gh(*args):
    return subprocess.check_output(['gh', *map(str, args)], text=True).strip()


def api(path):
    return json.loads(gh('api', f'repos/{REPO}/{path}'))


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_packages(inventories):
    result = set()
    for inventory in inventories:
        for package in inventory['packages']:
            fields = dict(line.split(': ', 1) for line in package['metadata'].splitlines() if ': ' in line)
            source = re.fullmatch(r'([^ ]+)(?: \(([^)]+)\))?', fields.get('Source', fields['Package']))
            assert source, fields
            result.add((source[1], source[2] or re.sub(r'\+b\d+$', '', fields['Version'])))
    return result


def validate_proof(proof, platform, tree_lookup, source_tree):
    assert proof['schema'] == 1 and proof['platform'] == platform
    check = proof['packagedRuntimeCheck']
    assert check['passed'] and set(check['languages']) == LANGUAGES
    assert all(entry['passed'] for entry in check['languages'].values())
    assert tree_lookup(proof['commit']) == source_tree
    assert len(proof['files']) == (6 if platform == 'linux' else 2)
    for item in proof['files']:
        assert Path(item['name']).name == item['name']
        assert item['name'].startswith('DevCat-0.9.2-')
        assert 0 < item['bytes'] < 2 * 1024**3
        assert re.fullmatch(r'[a-f0-9]{64}', item['sha256'])


def main(plan_file):
    path = Path(plan_file)
    assert path == Path('docs/releases/v0.9.2-prerelease-plan.json')
    plan = json.loads(path.read_text())
    assert plan['tag'] == 'v0.9.2' and plan['version'] == '0.9.2'
    assert re.fullmatch('[a-f0-9]{40}', plan['source_sha'])
    assert os.environ.get('GITHUB_REPOSITORY', REPO) == REPO
    assert api(f"git/commits/{plan['source_sha']}")['tree']['sha'] == plan['source_tree']
    # Release metadata may differ; application and runtime inputs must not.
    subprocess.run(['git', 'diff', '--exit-code', plan['source_sha'], 'HEAD', '--',
                    'apps/devcat_flutter', 'assets_source', 'content', 'packages', 'third_party',
                    'scripts/android_runtime_versions.json', 'scripts/desktop_runtime_versions.json',
                    'scripts/build_android_rootfs.py', 'scripts/build_android_proot.sh'], check=True)
    deadline = time.monotonic() + 30 * 60
    while True:
        run = api(f"actions/runs/{plan['build_run']}")
        assert run['head_sha'] == plan['source_sha']
        if run['status'] == 'completed':
            assert run['conclusion'] == 'success', run['conclusion']
            break
        if time.monotonic() > deadline:
            raise TimeoutError('Candidate CI has not completed; nothing published')
        print('Waiting for the reviewed candidate CI to finish', flush=True)
        time.sleep(30)
    jobs = api(f"actions/runs/{plan['build_run']}/jobs?per_page=100")['jobs']
    assert len(jobs) == 9 and all(job['conclusion'] == 'success' for job in jobs)
    artifacts = {a['name']: a for a in api(f"actions/runs/{plan['build_run']}/artifacts?per_page=100")['artifacts']}
    trees = {}
    def tree_lookup(commit):
        if commit not in trees:
            trees[commit] = api(f'git/commits/{commit}')['tree']['sha']
        return trees[commit]
    release_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    notes = Path(plan['notes'])
    assert notes == Path('docs/RELEASE_NOTES_0.9.2.md') and notes.is_file()
    try:
        existing = json.loads(gh('release', 'view', plan['tag'], '--repo', REPO, '--json', 'isDraft,targetCommitish'))
    except subprocess.CalledProcessError:
        existing = None
    if existing:
        assert existing['isDraft'], 'Never overwrite an already published release'
        assert existing['targetCommitish'] == release_commit
    else:
        gh('release', 'create', plan['tag'], '--repo', REPO, '--target', release_commit,
           '--title', 'DevCat 0.9.2 — предварительный выпуск', '--draft', '--prerelease',
           '--latest=false', '--notes-file', notes)
    checksums = {}
    sizes = {}
    def upload(file):
        assert file.is_file() and 0 < file.stat().st_size < 2 * 1024**3
        digest = sha(file)
        if file.name in checksums:
            raise ValueError(f'Duplicate release asset: {file.name}')
        gh('release', 'upload', plan['tag'], file, '--repo', REPO, '--clobber')
        checksums[file.name] = digest
        sizes[file.name] = file.stat().st_size
        print(f'Uploaded and hashed {file.name}: {file.stat().st_size} bytes', flush=True)
    with tempfile.TemporaryDirectory(prefix='devcat-prerelease-') as temp:
        work = Path(temp)
        proofs = {}
        for platform in ['windows', 'macos', 'linux']:
            name = f'devcat-desktop-proof-{platform}'
            assert name in artifacts and not artifacts[name]['expired']
            folder = work/name
            gh('run', 'download', plan['build_run'], '--repo', REPO, '--name', name, '--dir', folder)
            files = list(folder.glob('*.json'))
            assert len(files) == 1
            proof = json.loads(files[0].read_text())
            validate_proof(proof, platform, tree_lookup, plan['source_tree'])
            proofs[platform] = proof
            files[0].rename(folder/f'DevCat-0.9.2-{platform}-build-proof.json')
            upload(folder/f'DevCat-0.9.2-{platform}-build-proof.json')
        for platform in ['windows', 'macos', 'linux']:
            name = f'devcat-{platform}'
            assert name in artifacts and not artifacts[name]['expired']
            assert shutil.disk_usage(work).free > 2*artifacts[name]['size_in_bytes'] + 1024**3
            folder = work/name
            gh('run', 'download', plan['build_run'], '--repo', REPO, '--name', name, '--dir', folder)
            expected = {item['name']: item for item in proofs[platform]['files']}
            actual = {file.name for file in folder.iterdir()}
            assert actual == set(expected), (actual, set(expected))
            for file in sorted(folder.iterdir()):
                assert file.stat().st_size == expected[file.name]['bytes']
                assert sha(file) == expected[file.name]['sha256'], file.name
                upload(file)
                file.unlink()
            folder.rmdir()
        name = 'devcat-android-build-inputs-universal'
        assert name in artifacts and not artifacts[name]['expired']
        android = work/'android'
        gh('run', 'download', plan['build_run'], '--repo', REPO, '--name', name, '--dir', android)
        apk = android/'app-release.apk'
        assert {file.name for file in android.iterdir()} == {'app-release.apk'}
        inventories = []
        with zipfile.ZipFile(apk) as archive:
            for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
                inventory = json.loads(archive.read(f'assets/runtime/{abi}.json'))
                assert inventory['abi'] == abi
                inventories.append(inventory)
        inventory_file = work/'DevCat-0.9.2-Android-runtimes.json'
        inventory_file.write_text(json.dumps({'schema':1, 'version':'0.9.2', 'buildRun':plan['build_run'],
            'buildCommit':plan['source_sha'], 'runtimes':inventories}, indent=2)+'\n')
        upload(inventory_file)
        apk = apk.rename(android/'DevCat-0.9.2-android-universal-test.apk')
        upload(apk)
        apk.unlink()
        sources = work/'sources'
        gh('release', 'download', plan['source_release'], '--repo', REPO, '--pattern', plan['source_asset'],
           '--pattern', 'SHA256SUMS', '--dir', sources)
        previous_sums = dict((name, digest) for digest, name in
            (line.split('  ', 1) for line in (sources/'SHA256SUMS').read_text().splitlines()))
        source_tar = sources/plan['source_asset']
        assert sha(source_tar) == previous_sums[source_tar.name]
        with tarfile.open(source_tar) as archive:
            source_manifest = json.load(archive.extractfile('SOURCE_MANIFEST.json'))
            assert source_packages(inventories) <= {tuple(p) for p in source_manifest['packages']}
            config = json.loads(Path('scripts/android_runtime_versions.json').read_text())
            assert source_manifest['javaSource'] == config['javaSources']
            for item in source_manifest['files']:
                member = archive.getmember(item['name'])
                assert member.isfile() and member.size == item['bytes']
                assert hashlib.file_digest(archive.extractfile(member), 'sha256').hexdigest() == item['sha256']
        source_tar = source_tar.rename(sources/'DevCat-0.9.2-android-runtime-sources.tar')
        upload(source_tar)
        source_tar.unlink()
        for source, name in [
            ('docs/SBOM.spdx.json','DevCat-0.9.2-SBOM.spdx.json'),
            ('docs/THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md'),
            ('LICENSE','LICENSE'),
            ('docs/DevCat-lectures.zip','DevCat-0.9.2-lectures.zip'),
            ('docs/DevCat-0.9.2-appearance-animations.zip','DevCat-0.9.2-appearance-animations.zip'),
        ]:
            file = work/name
            shutil.copyfile(source, file)
            upload(file)
            file.unlink()
        info = {'schema':1, 'version':'0.9.2', 'prerelease':True, 'releaseCommit':release_commit,
            'sourceCommit':plan['source_sha'], 'sourceTree':plan['source_tree'],
            'buildRun':plan['build_run'], 'jobs':[{k:job[k] for k in ['id','name','conclusion']} for job in jobs],
            'artifacts':[{k:a.get(k) for k in ['id','name','size_in_bytes','digest']} for a in artifacts.values()],
            'androidSigning':'temporary CI debug key; not an upgrade from v0.9.1',
            'androidVersionCode':5009, 'macosSigning':'ad-hoc; not notarized'}
        info_file = work/'DevCat-0.9.2-build-info.json'
        info_file.write_text(json.dumps(info,indent=2)+'\n')
        upload(info_file)
        sums = work/'SHA256SUMS'
        sums.write_text(''.join(f'{digest}  {name}\n' for name,digest in sorted(checksums.items())))
        upload(sums)
    releases = api('releases?per_page=100')
    release = next(item for item in releases if item['tag_name'] == plan['tag'])
    assert release['draft'] and release['prerelease']
    assets = {item['name']:item for item in release['assets']}
    assert set(assets) == set(checksums), (set(assets),set(checksums))
    for name,item in assets.items():
        assert item['state'] == 'uploaded' and item['size'] == sizes[name], name
        digest = item.get('digest')
        if digest:
            assert digest == 'sha256:'+checksums[name], name
    gh('release', 'edit', plan['tag'], '--repo', REPO, '--draft=false', '--prerelease', '--latest=false', '--notes-file', notes)
    print(gh('release','view',plan['tag'],'--repo',REPO,'--json','url,isDraft,isPrerelease,assets'),flush=True)


if __name__ == '__main__':
    main(sys.argv[1])
