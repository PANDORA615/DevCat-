"""Optional owner-provided Actions secrets. Never print secret values."""
import base64,os
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'apps/devcat_flutter/android'
if os.getenv('KEYSTORE'):
 (root/'app/release.jks').write_bytes(base64.b64decode(os.environ['KEYSTORE']))
 # Environment is consumed directly by Gradle, no passwords written to the repository.
 (root/'owner-signing.enabled').write_text('enabled')
else:
 print('No owner signing secrets; these are build inputs, not publishable Android packages. Sign with the persistent owner key before release.')
