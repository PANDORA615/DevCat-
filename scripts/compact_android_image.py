"""Remove optional SDK payloads; retain offline compilers and standard libraries.

Applied after the existing pinned image cache, so compaction changes packaging,
not compiler versions or the corresponding-source provenance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

PROFILE = 'devcat-offline-compact-1'


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def optional(name):
    parts = name.split('/')
    if name == 'opt/java/lib/src.zip':
        return True  # Corresponding sources are a separate release asset.
    if name.startswith('opt/node/include/'):
        return True  # No native-addon build/package manager UI is provided.
    if name.startswith('opt/dotnet/templates/'):
        return True
    if name.startswith('opt/dotnet/sdk/') and len(parts) > 4:
        return parts[4] in {'DotnetTools', 'FSharp', 'Containers', 'TestHostNetFramework'}
    return False


def compact(folder):
    for metadata_file in sorted(folder.glob('*.json')):
        metadata = json.loads(metadata_file.read_text())
        if 'abi' not in metadata or 'sha256' not in metadata:
            continue
        image = folder / (metadata['abi'] + '.zip')
        if metadata.get('imageProfile') == PROFILE:
            assert checksum(image) == metadata['sha256']
            continue
        before = image.stat().st_size
        assert checksum(image) == metadata['sha256']
        temporary = image.with_suffix('.compact.zip')
        removed_bytes = 0
        removed_files = 0
        unpacked = 0
        with zipfile.ZipFile(image) as source, zipfile.ZipFile(
            temporary, 'w', zipfile.ZIP_DEFLATED, compresslevel=9
        ) as target:
            names = {i.filename for i in source.infolist() if not optional(i.filename)}
            # Keep all runtime libraries, reference assemblies, compiler binaries,
            # package metadata and legal notices. Only the explicit allowlist above
            # may remove files, not filename extensions or guessed dependencies.
            for item in source.infolist():
                if optional(item.filename):
                    removed_bytes += item.file_size
                    removed_files += 1
                    continue
                data = source.read(item)
                if item.filename == '_devcat_links.json':
                    links = json.loads(data)
                    data = json.dumps({k: v for k, v in links.items() if not optional(k)}).encode()
                elif item.filename == '_devcat_inventory.json':
                    continue
                else:
                    unpacked += item.file_size
                entry = zipfile.ZipInfo(item.filename, date_time=(2026, 10, 29, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = item.external_attr
                target.writestr(entry, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
            assert any(n.endswith('/Roslyn/bincore/csc.dll') for n in names)
            assert any(n.endswith('/ref/net8.0/System.Runtime.dll') for n in names)
            assert 'opt/java/bin/javac' in names and 'opt/java/lib/modules' in names
            assert 'opt/node/bin/node' in names and 'usr/local/go/bin/go' in names
            inventory = {k: v for k, v in metadata.items() if k not in {'bytes', 'sha256'}}
            inventory.update(imageProfile=PROFILE, unpackedBytes=unpacked,
                             removedOptionalFiles=removed_files,
                             removedOptionalBytes=removed_bytes)
            entry = zipfile.ZipInfo('_devcat_inventory.json', date_time=(2026, 10, 29, 0, 0, 0))
            target.writestr(entry, json.dumps(inventory, indent=2), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        assert removed_files > 0 and temporary.stat().st_size < before
        temporary.replace(image)
        metadata.update(inventory, bytes=image.stat().st_size, sha256=checksum(image),
                        originalCompressedBytes=before)
        # A freshly built Docker image leaves root-owned, read-only-for-runner
        # metadata in this writable output directory. Replace it atomically,
        # just as we replace the image, rather than opening that inode to write.
        temporary_metadata = metadata_file.with_suffix('.compact.json')
        temporary_metadata.write_text(json.dumps(metadata, indent=2) + '\n')
        temporary_metadata.replace(metadata_file)
        print(metadata['abi'], before, '->', metadata['bytes'], 'bytes; all execution components retained', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    compact(parser.parse_args().folder)
