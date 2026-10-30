"""Sign CI Android build inputs with the owner's persistent key (never print passwords)."""
import argparse, subprocess, tempfile, zipfile
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('inputs',type=Path);p.add_argument('output',type=Path)
p.add_argument('--keystore',required=True,type=Path);p.add_argument('--password-file',required=True,type=Path)
p.add_argument('--build-tools',required=True,type=Path);p.add_argument('--version',default='0.6.0');p.add_argument('--alias',default='devcat')
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
for apk in sorted(a.inputs.glob('*.apk')):
 abi=apk.name.removeprefix('app-').removesuffix('-release.apk') if apk.name!='app-release.apk' else 'universal'
 destination=a.output/f'DevCat-{a.version}-android-{abi}.apk'
 with tempfile.TemporaryDirectory(prefix='devcat-sign-') as temp:
  aligned=Path(temp)/'aligned.apk'
  subprocess.run([str(a.build_tools/'zipalign'),'-P','16','-f','4',str(apk),str(aligned)],check=True)
  subprocess.run([str(a.build_tools/'apksigner'),'sign','--ks',str(a.keystore),'--ks-pass',f'file:{a.password_file}','--ks-key-alias',a.alias,'--v4-signing-enabled','false','--out',str(destination),str(aligned)],check=True)
  subprocess.run([str(a.build_tools/'apksigner'),'verify','--verbose','--print-certs',str(destination)],check=True)
  subprocess.run([str(a.build_tools/'zipalign'),'-c','-P','16','4',str(destination)],check=True)
for bundle in sorted(a.inputs.glob('*.aab')):
 destination=a.output/f'DevCat-{a.version}-android.aab'
 with zipfile.ZipFile(bundle) as source,zipfile.ZipFile(destination,'w') as target:
  for info in source.infolist():
   name=info.filename.upper()
   if name=='META-INF/MANIFEST.MF' or (name.startswith('META-INF/') and name.endswith(('.SF','.RSA','.DSA','.EC'))):continue
   target.writestr(info,source.read(info.filename))
 subprocess.run(['jarsigner','-keystore',str(a.keystore),'-storepass:file',str(a.password_file),'-sigalg','SHA256withRSA','-digestalg','SHA-256',str(destination),a.alias],check=True)
 subprocess.run(['jarsigner','-verify',str(destination)],check=True)
