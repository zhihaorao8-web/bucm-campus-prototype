"""Synchronize public assets, pinned HSSF dependencies and manifest version for Flutter."""
from pathlib import Path
import re
import shutil
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependencies import dependencies


def main():
    app = ROOT / 'mobile'
    from scripts.iconmcp_assets import check_assets
    check_assets()
    shutil.copytree(ROOT / 'design/icons/iconmcp', app / 'assets/icons/iconmcp', dirs_exist_ok=True)
    target = app / 'android/app'
    if not (target / 'build.gradle.kts').exists():
        raise SystemExit('Generate the Android host with flutter create first; see docs/FLUTTER.md.')
    for name in ('extract.js', 'school-viewport.js', 'export-nav.js', 'coverage-check.js', 'classroom.js', 'classroom-entry.js', 'recording-api-bridge.js', 'recording-api.cjs', 'library-seat-read.js', 'library-seat-write.js'):
        (app / 'assets').mkdir(exist_ok=True)
        shutil.copyfile(ROOT / 'assets' / name, app / 'assets' / name)
    # Shared user-supplied artwork; generated Flutter assets remain ignored.
    shutil.copyfile(ROOT / 'design/branding/app-icon.png', app / 'assets/app-icon.png')
    shutil.copyfile(ROOT / 'design/branding/developer-avatar.png', app / 'assets/developer-avatar.png')
    parser_folder = target / 'src/main/java/cn/bucm/campusprobe'
    parser_folder.mkdir(parents=True, exist_ok=True)
    for name in ('ScheduleParser', 'CourseTimes', 'CourseImportPlan', 'AcademicTerm', 'ExportWorkbook', 'SchoolExport', 'ClassroomMediaTransport'):
        shutil.copyfile(ROOT / 'src/cn/bucm/campusprobe' / (name + '.java'), parser_folder / (name + '.java'))
    native_assets = target / 'src/main/assets'
    native_assets.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'assets/classroom-player.js', native_assets / 'classroom-player.js')
    license_path = native_assets / 'third-party'
    license_path.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / 'assets/third-party', license_path, dirs_exist_ok=True)
    jars = target / 'libs'
    jars.mkdir(exist_ok=True)
    import zipfile
    for jar in dependencies():
        shutil.copyfile(jar, jars / jar.name)
        with zipfile.ZipFile(jar) as archive:
            for entry in archive.namelist():
                if entry.startswith('META-INF/') and Path(entry).name.upper().startswith(('LICENSE', 'NOTICE')) and not entry.endswith('/'):
                    folder = license_path / jar.stem
                    folder.mkdir(exist_ok=True)
                    (folder / Path(entry).name).write_bytes(archive.read(entry))
    manifest = ET.parse(ROOT / 'AndroidManifest.xml').getroot()
    ns = '{http://schemas.android.com/apk/res/android}'
    display_version = manifest.get(ns + 'versionName')
    # Android accepts the requested 0.1 label; pub requires a three-part SemVer.
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', display_version):
        raise SystemExit('Unsupported Android versionName format.')
    package_version = display_version + '.0' if display_version.count('.') == 1 else display_version
    version = package_version + '+' + manifest.get(ns + 'versionCode')
    pubspec = app / 'pubspec.yaml'
    content = re.sub(r'^version:.*$', 'version: ' + version, pubspec.read_text(encoding='utf-8'), flags=re.M)
    pubspec.write_text(content, encoding='utf-8')
    print('Prepared public scripts, verified XLS dependencies and licenses; Android ' + display_version + ', pubspec ' + version)


if __name__ == '__main__':
    main()
