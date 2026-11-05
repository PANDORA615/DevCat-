"""Stage the released Android source in an empty directory; leave desktop intact."""
import argparse
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def stage(repo, commit, destination, version):
    destination = Path(destination)
    if destination.exists():
        raise ValueError('Output must not exist; existing files are never overwritten')
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Pin an exact source commit')
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?\+\d+', version):
        raise ValueError('Expected a semantic app version with build number')
    archive = subprocess.check_output(
        ['git', 'archive', commit, 'apps/devcat_flutter'], cwd=repo)
    with tempfile.TemporaryDirectory(prefix='devcat-android-source-') as directory:
        with tarfile.open(fileobj=io.BytesIO(archive)) as source:
            # Source is committed, nevertheless reject traversal and links.
            for member in source.getmembers():
                if (member.issym() or member.islnk() or
                    not (member.isfile() or member.isdir()) or
                    '..' in Path(member.name).parts or Path(member.name).is_absolute()):
                    raise ValueError('Invalid source archive member')
            source.extractall(directory, filter='data')
        tree = Path(directory) / 'apps/devcat_flutter'
        spec = tree / 'pubspec.yaml'
        old = spec.read_text()
        updated, count = re.subn(r'^version: .+$', f'version: {version}', old, flags=re.M)
        if count != 1:
            raise ValueError('Expected exactly one application version')
        spec.write_text(updated)
        # copytree works across filesystems; it cannot overwrite existing data.
        import shutil
        shutil.copytree(tree, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    config = json.loads((ROOT / 'config/android-baseline.json').read_text())
    spec = (ROOT / 'apps/devcat_flutter/pubspec.yaml').read_text()
    version = re.search(r'^version: (\S+)$', spec, re.M).group(1)
    stage(ROOT, config['source_commit'], args.output, version)
    build = config['build_number_offset'] + int(version.split('+')[1])
    print(json.dumps({'source_commit': config['source_commit'],
                      'version': version, 'android_version_code': build}))
    import os
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'build_number={build}\n')


if __name__ == '__main__':
    main()
