"""The same generated cat supplied as a small SVG-wrapped local image for web labs."""
from pathlib import Path
import base64,json
ROOT=Path(__file__).resolve().parents[1]
CAT_SVG='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="320" height="320" viewBox="0 0 192 192"><image width="192" height="192" xlink:href="data:image/png;base64,'+base64.b64encode((ROOT/'apps/devcat_flutter/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png').read_bytes()).decode()+'"/></svg>'
if __name__=='__main__':
 (ROOT/'apps/devcat_flutter/lib/core/web_sample_assets.dart').write_text('// Generated from the DevCat launcher image by scripts/web_sample_assets.py.\nconst webSampleCat = '+json.dumps(CAT_SVG)+';\n')
