"""Preserve license texts from the exact offline Android execution images."""
import argparse
import hashlib
from pathlib import Path
import zipfile

repo = Path(__file__).resolve().parent.parent


def generate(images, output):
    texts = {}

    def add(label, data):
        digest = hashlib.sha256(data).hexdigest()
        record = texts.setdefault(digest, {'text': data.decode('utf-8', errors='replace'), 'labels': []})
        record['labels'].append(label)

    for relative in ['third_party/proot/COPYING', 'third_party/proot/AUTHORS', 'third_party/talloc/LICENSE']:
        add(relative, (repo / relative).read_bytes())
    for image in images:
        with zipfile.ZipFile(image) as archive:
            for name in archive.namelist():
                basename = name.rsplit('/', 1)[-1].lower()
                if (name.startswith('usr/share/doc/') and basename == 'copyright' or
                    name.startswith('opt/java/legal/') or
                    basename in {'license', 'license.txt', 'license.md', 'thirdpartynotices.txt', 'patents', 'authors'}):
                    add(f'{image.stem}/{name}', archive.read(name))
    lines = ['# Android runtime license notices\n\nOriginal license texts from the bundled execution images. App source is MIT; these independent runtimes retain their own licenses. Corresponding GPL/LGPL sources accompany the release.\n']
    for record in texts.values():
        lines.append('\n## ' + ' · '.join(record['labels']) + '\n\n```text\n' + record['text'] + '\n```\n')
    output.write_text(''.join(lines))
    print(f'{len(texts)} distinct license texts, {output.stat().st_size} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('images', nargs='+', type=Path)
    args = parser.parse_args()
    generate(args.images, args.output)
