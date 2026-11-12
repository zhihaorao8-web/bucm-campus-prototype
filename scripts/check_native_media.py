"""Generate synthetic local HLS and optionally check the isolated Android player.

No school URLs, accounts, network server or changes to the user's app data.
FFmpeg is a development tool, never packaged in the application.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'mobile/build/app/generated/synthetic-media'


def generate(ffmpeg):
    (ROOT / 'build').mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if not OUTPUT.resolve().is_relative_to((ROOT / 'mobile/build').resolve()):
        raise SystemExit('Synthetic output escaped the build directory.')
    with tempfile.TemporaryDirectory(prefix='synthetic-hls-', dir=ROOT / 'build') as staging:
        staging = Path(staging)
        subprocess.run([
            ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
            '-f', 'lavfi', '-i', 'testsrc2=size=160x96:rate=10',
            '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=22050',
            '-t', '60', '-map_metadata', '-1', '-c:v', 'libx264',
            '-profile:v', 'baseline', '-pix_fmt', 'yuv420p', '-preset', 'ultrafast',
            '-crf', '35', '-g', '20', '-keyint_min', '20', '-sc_threshold', '0',
            '-c:a', 'aac', '-ac', '1', '-b:a', '16k', '-af', 'volume=0.03',
            '-f', 'hls', '-hls_time', '2', '-hls_playlist_type', 'vod',
            '-hls_segment_filename', str(staging / 'segment-%03d.ts'),
            str(staging / 'index.m3u8'),
        ], check=True)
        playlist = (staging / 'index.m3u8').read_text(encoding='utf-8')
        parts = [line for line in playlist.splitlines() if line and not line.startswith('#')]
        if not parts or any(not re.fullmatch(r'segment-\d{3}\.ts', part) for part in parts):
            raise SystemExit('Fixture playlist must reference relative synthetic TS assets only.')
        if '#EXT-X-ENDLIST' not in playlist:
            raise SystemExit('Fixture is not a finite VOD playlist.')
        files = []
        for name in ['index.m3u8', *parts]:
            content = (staging / name).read_bytes()
            (OUTPUT / name).write_bytes(content)
            files.append({'file': name, 'sha256': hashlib.sha256(content).hexdigest()})
        (OUTPUT / 'fixture.json').write_text(json.dumps({
            'schema': 1, 'synthetic': True, 'seconds': 60, 'files': files,
            'recipe': 'lavfi testsrc2 160x96/10fps + low-level 440Hz sine, H264 baseline/AAC HLS VOD',
        }, indent=2) + '\n', encoding='utf-8')
    print(f'Generated and hashed {len(files)} synthetic HLS assets; no school content.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    parser.add_argument('--device', help='Run isolated instrumentation on the only attached emulator.')
    args = parser.parse_args()
    if not args.ffmpeg or not Path(args.ffmpeg).is_file():
        parser.error('Provide --ffmpeg with a local FFmpeg executable (or add it to PATH).')
    generate(str(Path(args.ffmpeg).resolve()))
    if not args.device:
        return
    if not re.fullmatch(r'emulator-\d+', args.device):
        parser.error('This local check accepts an emulator, not a physical device.')
    sdk = os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
    adb = Path(sdk) / 'platform-tools' / ('adb.exe' if os.name == 'nt' else 'adb') if sdk else None
    if adb is None or not adb.is_file():
        parser.error('Set ANDROID_SDK_ROOT to the existing Android SDK.')
    inventory = subprocess.check_output([str(adb), 'devices'], text=True)
    devices = [line.split()[0] for line in inventory.splitlines() if re.search(r'\sdevice$', line)]
    if devices != [args.device]:
        parser.error('Only the explicitly selected emulator may be online for this check.')
    qemu = subprocess.check_output([str(adb), '-s', args.device, 'shell', 'getprop', 'ro.kernel.qemu'], text=True).strip()
    if qemu != '1':
        parser.error('Selected target did not identify itself as an emulator.')
    env = os.environ.copy()
    env['ANDROID_SERIAL'] = args.device
    gradle = ROOT / 'mobile/android' / ('gradlew.bat' if os.name == 'nt' else 'gradlew')
    sources = [ROOT / 'mobile/android/app/src/main/java/cn/bucm/campus_schedule' / name
               for name in ['ClassroomPlayback.java', 'ClassroomPlayerGroup.java', 'ClassroomDataSource.java']]
    sources += [ROOT / 'mobile/android/app/src/mediaTest/java/cn/bucm/campus_schedule/MediaPlaybackTest.java',
                ROOT / 'mobile/android/app/build.gradle.kts']
    fingerprints = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    summary = ROOT / 'build/native-media-summary.json'
    summary.unlink(missing_ok=True)
    started = time.time()
    # A qualified task avoids running unrelated plugins' own instrumentation.
    subprocess.run([str(gradle), ':app:connectedDebugAndroidTest', '-PcampusMediaTest=true', '--info'],
                   cwd=ROOT / 'mobile/android', env=env, check=True)
    reports = ROOT / 'mobile/build/app/outputs/androidTest-results/connected/debug'
    cases = []
    for report in reports.rglob('*.xml'):
        if report.stat().st_mtime < started - 2:
            continue
        tree = ET.parse(report)
        for case in tree.iter('testcase'):
            if case.get('classname') == 'cn.bucm.campus_schedule.MediaPlaybackTest':
                if case.find('failure') is not None or case.find('error') is not None or case.find('skipped') is not None:
                    raise SystemExit('Native media case did not pass; inspect the fresh JUnit report.')
                cases.append(case.get('name'))
    expected = {'decodePauseUnifiedSeekSpeedAndAudio', 'layoutKeepsPositionAndReleasesDroppedDecoders',
                'missingLocalAssetReportsErrorAndStops'}
    if set(cases) != expected or len(cases) != 3:
        raise SystemExit('Fresh JUnit reports did not include all three native media checks.')
    if fingerprints != {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}:
        raise SystemExit('Native sources changed during the check; rerun against a stable tree.')
    summary.write_text(json.dumps({
        'passed': sorted(cases), 'target': 'cn.bucm.campus_schedule.mediatest',
        'seconds': round(time.time() - started, 2), 'nativeSources': fingerprints,
        'fixtureSHA256': hashlib.sha256((OUTPUT / 'fixture.json').read_bytes()).hexdigest(),
    }, indent=2) + '\n', encoding='utf-8')
    print('Verified all 3 fresh native synthetic media checks; summary saved under build/.', flush=True)


if __name__ == '__main__':
    main()
