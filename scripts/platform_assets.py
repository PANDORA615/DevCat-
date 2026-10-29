"""Convert the generated original icon to required launcher resource formats."""
from pathlib import Path
from PIL import Image
import json
root=Path(__file__).resolve().parents[1]
app=root/'apps/devcat_flutter'
icon=Image.open(app/'assets/branding/icon.png').convert('RGB')
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
 icon.resize((size,size),Image.Resampling.NEAREST).save(app/f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
for size in [16,32,64,128,256,512,1024]:
 icon.resize((size,size),Image.Resampling.NEAREST).save(app/f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png')
icon.resize((256,256),Image.Resampling.NEAREST).save(app/'windows/runner/resources/app_icon.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
icon.resize((512,512),Image.Resampling.NEAREST).save(root/'packages/cat_assets/devcat.png')
