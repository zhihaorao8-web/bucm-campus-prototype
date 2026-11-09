"""Build the Java prototype with official Android tools; no Gradle dependency.

python build.py --sdk PATH_TO_SDK --work build/local --output dist
The work directory owns the persistent development signing key. Never commit it.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from scripts.dependencies import dependencies

ROOT = Path(__file__).resolve().parent
EXE = '.exe' if os.name == 'nt' else ''


def run(*args):
    subprocess.run([str(value) for value in args], check=True)


def java_tools():
    configured = os.environ.get('JAVA_HOME')
    if configured and (Path(configured) / 'bin' / ('javac' + EXE)).exists():
        return Path(configured) / 'bin'
    executable = shutil.which('javac')
    if not executable:
        raise SystemExit('JDK 17+ is required; set JAVA_HOME or add javac to PATH.')
    return Path(executable).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', required=True)
    parser.add_argument('--work', default=str(ROOT / 'build' / 'local'))
    parser.add_argument('--output', default=str(ROOT / 'dist'))
    args = parser.parse_args()
    sdk, work, output = map(lambda value: Path(value).resolve(),
                            (args.sdk, args.work, args.output))
    work.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    platform = next((item for item in (sdk / 'platforms/android-35', sdk / 'android-35')
                     if (item / 'android.jar').is_file()), None)
    tools = next((item for item in (sdk / 'build-tools/35.0.0', sdk / 'android-15')
                  if (item / ('aapt2' + EXE)).is_file()), None)
    if platform is None or tools is None:
        raise SystemExit('Install Android SDK platform 35 and build-tools 35.0.0.')
    java = java_tools()
    deps=dependencies()
    dependency_classpath=os.pathsep.join(str(p) for p in deps)
    # A fresh run directory prevents stale class or DEX files entering a new APK.
    stage = Path(tempfile.mkdtemp(prefix='run-', dir=work)).resolve()
    if not stage.is_relative_to(work):
        raise SystemExit('Build stage must remain inside the requested work directory.')
    classes, dex = stage / 'classes', stage / 'dex'
    classes.mkdir()
    dex.mkdir()
    android = platform / 'android.jar'
    manifest = ET.parse(ROOT / 'AndroidManifest.xml').getroot()
    namespace = '{http://schemas.android.com/apk/res/android}'
    version = manifest.get(namespace + 'versionName')
    minimum = manifest.find('uses-sdk').get(namespace + 'minSdkVersion')

    run(java / ('javac' + EXE), '--release', '8', '-encoding', 'UTF-8',
        '-classpath', str(android)+os.pathsep+dependency_classpath, '-d', classes, *sorted((ROOT / 'src').rglob('*.java')))
    run(java / ('javac' + EXE), '--release', '8', '-encoding', 'UTF-8',
        '-classpath',str(classes)+os.pathsep+dependency_classpath, '-d', classes, *sorted((ROOT/'tests').glob('*.java')))
    for test in ('ParserTest','ExportTest','CourseTimeTest'):
        run(java / ('java' + EXE), '-cp',str(classes)+os.pathsep+dependency_classpath,test)
    with zipfile.ZipFile(stage / 'classes.jar', 'w') as archive:
        for file in sorted((classes / 'cn').rglob('*.class')):
            archive.write(file, file.relative_to(classes).as_posix())
    dex_inputs=[]
    for dependency in deps:
        clean=stage/dependency.name
        with zipfile.ZipFile(dependency) as source,zipfile.ZipFile(clean,'w',zipfile.ZIP_DEFLATED) as target:
            for item in source.namelist():
                if item.endswith('.class') and not item.startswith('META-INF/') and item!='module-info.class':target.writestr(item,source.read(item))
        dex_inputs.append(clean)
    run(java / ('java' + EXE), '-cp', tools / 'lib/d8.jar',
        'com.android.tools.r8.D8', '--lib', android, '--min-api', minimum,
        '--output', dex, stage / 'classes.jar',*dex_inputs)
    run(tools / ('aapt2' + EXE), 'compile', '--dir', ROOT / 'res',
        '-o', stage / 'resources.zip')
    run(tools / ('aapt2' + EXE), 'link', '--manifest', ROOT / 'AndroidManifest.xml',
        '-I', android, '-A', ROOT / 'assets', '-o', stage / 'unsigned.apk',
        stage / 'resources.zip')
    with zipfile.ZipFile(stage / 'unsigned.apk', 'a', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(dex.glob('*.dex')):
            archive.write(file, file.name)
        for dependency in deps:
            with zipfile.ZipFile(dependency) as source:
                for name in source.namelist():
                    if name.startswith('META-INF/') and any(part in name.upper() for part in ('LICENSE','NOTICE')) and not name.endswith('/'):
                        archive.writestr('assets/third-party/'+dependency.stem+'/'+name.rsplit('/',1)[-1],source.read(name))
    run(tools / ('zipalign' + EXE), '-f', '4', stage / 'unsigned.apk',
        stage / 'aligned.apk')
    key = work / 'prototype.keystore'
    if not key.exists():
        run(java / ('keytool' + EXE), '-genkeypair', '-keystore', key,
            '-storepass', 'android', '-keypass', 'android', '-alias', 'prototype',
            '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650',
            '-dname', 'CN=BUCM Prototype Development')
    apk = output / ('bucm-campus-prototype-' + version + '.apk')
    run(java / ('java' + EXE), '-jar', tools / 'lib/apksigner.jar', 'sign',
        '--ks', key, '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
        '--out', apk, stage / 'aligned.apk')
    run(java / ('java' + EXE), '-jar', tools / 'lib/apksigner.jar',
        'verify', '--verbose', apk)
    run(tools / ('aapt2' + EXE), 'dump', 'badging', apk)
    print('Built:', apk)
    print('Development signing key (local only):', key)


if __name__ == '__main__':
    main()
