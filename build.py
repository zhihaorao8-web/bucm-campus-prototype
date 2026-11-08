"""Build with Python 3, JDK 17+, Android platform 35 and build-tools 35.
Usage: python build.py --sdk PATH_TO_SDK --work PATH_TO_SCRATCH
No Gradle, Maven dependencies, network access, or third-party app code required.
"""
import argparse, pathlib, shutil, subprocess, zipfile, xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--sdk',required=True);p.add_argument('--work',required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent;sdk=pathlib.Path(a.sdk).resolve();work=pathlib.Path(a.work).resolve();work.mkdir(parents=True,exist_ok=True)
platform=next((v for v in [sdk/'platforms/android-35',sdk/'android-35'] if (v/'android.jar').exists()),None)
tools=next((v for v in [sdk/'build-tools/35.0.0',sdk/'android-15'] if (v/'aapt.exe').exists()),None)
assert platform and tools,'Android SDK platform/build-tools 35 not found'
jar=platform/'android.jar';classes=work/'classes';classes.mkdir(exist_ok=True);dex=work/'dex';dex.mkdir(exist_ok=True);gen=work/'gen';gen.mkdir(exist_ok=True)
def run(*args):subprocess.run([str(x) for x in args],check=True)
java=pathlib.Path(shutil.which('java')).resolve().parent
sources=list((root/'src').rglob('*.java'))
run(java/'javac.exe','--release','8','-encoding','UTF-8','-classpath',jar,'-d',classes,*sources)
run(java/'javac.exe','--release','8','-encoding','UTF-8','-classpath',classes,'-d',classes,root/'tests/ParserTest.java')
run(java/'java.exe','-cp',classes,'ParserTest')
with zipfile.ZipFile(work/'classes.jar','w') as z:
 for f in (classes/'cn').rglob('*.class'):z.write(f,f.relative_to(classes).as_posix())
run(java/'java.exe','-cp',tools/'lib/d8.jar','com.android.tools.r8.D8','--lib',jar,'--min-api','26','--output',dex,work/'classes.jar')
run(tools/'aapt2.exe','compile','--dir',root/'res','-o',work/'resources.zip')
run(tools/'aapt2.exe','link','--manifest',root/'AndroidManifest.xml','-I',jar,'-A',root/'assets','-o',work/'unsigned.apk','--java',gen,work/'resources.zip')
with zipfile.ZipFile(work/'unsigned.apk','a',zipfile.ZIP_DEFLATED) as z:
 for f in dex.glob('*.dex'):z.write(f,f.name)
run(tools/'zipalign.exe','-f','4',work/'unsigned.apk',work/'aligned.apk')
key=work/'prototype.keystore'
if not key.exists():run(java/'keytool.exe','-genkeypair','-keystore',key,'-storepass','android','-keypass','android','-alias','prototype','-keyalg','RSA','-keysize','2048','-validity','3650','-dname','CN=BUCM Prototype Development')
version=ET.parse(root/'AndroidManifest.xml').getroot().get('{http://schemas.android.com/apk/res/android}versionName')
apk=root/('bucm-campus-prototype-'+version+'.apk')
run(java/'java.exe','-jar',tools/'lib/apksigner.jar','sign','--ks',key,'--ks-pass','pass:android','--key-pass','pass:android','--out',apk,work/'aligned.apk')
run(java/'java.exe','-jar',tools/'lib/apksigner.jar','verify','--verbose',apk)
run(tools/'aapt.exe','dump','badging',apk)
print('Built:',apk)
