"""Sign exact JSON payload bytes with an owner-supplied Ed25519 PEM key.

Requires Python cryptography. The private key is never copied into the output.
Keep the key outside the repository and pin the public key in the app build.
"""
import argparse
import base64
import json
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--payload', required=True, type=Path)
    parser.add_argument('--private-key', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    payload = args.payload.read_bytes()
    data = json.loads(payload)
    if data.get('schemaVersion') != 1 or data.get('channel') not in ('stable', 'beta'):
        parser.error('Unsupported manifest schema/channel')
    key = serialization.load_pem_private_key(args.private_key.read_bytes(), password=None)
    if not isinstance(key, Ed25519PrivateKey):
        parser.error('Expected an Ed25519 private key')
    args.output.write_text(json.dumps({
        'payload': base64.b64encode(payload).decode(),
        'signature': base64.b64encode(key.sign(payload)).decode(),
    }, indent=2) + '\n')
    public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    print('DEVCAT_UPDATE_PUBLIC_KEY=' + base64.b64encode(public).decode())


if __name__ == '__main__':
    main()
