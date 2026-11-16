"""Read-only dual-APK verification. Never signs, installs, tags or publishes."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'zhihaorao8-web/bucm-campus-prototype'
FLUTTER_SHA = 'c197ca5199e9ee5661e865596c9c07294dfab51c'
PACKAGE = 'cn.bucm.campus_schedule'


def exact(value, size):
    if not re.fullmatch('[0-9a-f]{' + str(size) + '}', value):
        raise ValueError('Expected an exact lowercase SHA digest.')
    return value


def command(*args):
    return subprocess.check_output([str(a) for a in args], stderr=subprocess.STDOUT).decode('utf-8', errors='replace')


def file_digest(path, algorithm='sha256'):
    # hashlib.file_digest starts at Python 3.11; keep the project's 3.10 floor.
    digest = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def source_assets(source):
    exact(source, 40)
    manifest = ET.fromstring(command('git', '-C', ROOT, 'show', source + ':AndroidManifest.xml'))
    ns = '{http://schemas.android.com/apk/res/android}'
    version, code = manifest.get(ns + 'versionName'), manifest.get(ns + 'versionCode')
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', version or '') or not (code or '').isdigit():
        raise ValueError('Unsupported source version.')
    old_adapter = command('git', '-C', ROOT, 'ls-tree', '-r', '--name-only', source,
                          'scripts/research/recording-api.cjs').strip()
    data = subprocess.check_output(['git', '-C', str(ROOT), 'archive', '--format=zip', source,
                                    'assets', 'design', *([old_adapter] if old_adapter else [])])
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        values = {name: archive.read(name) for name in archive.namelist() if not name.endswith('/')}
    expected = {'assets/classroom-player.js': values['assets/classroom-player.js']}
    scripts = ['extract.js', 'school-viewport.js', 'export-nav.js', 'coverage-check.js',
               'classroom.js', 'classroom-entry.js', 'recording-api-bridge.js', 'recording-api.cjs']
    for name in scripts:
        key = 'assets/' + name
        value = values.get(key)
        if value is None and name == 'recording-api.cjs':
            value = values.get(old_adapter)
        if value is None:
            raise ValueError('Source lacks a required public adapter.')
        expected['assets/flutter_assets/assets/' + name] = value
    for name, content in values.items():
        if name.startswith('design/icons/iconmcp/'):
            expected['assets/flutter_assets/assets/icons/iconmcp/' + name.split('design/icons/iconmcp/')[1]] = content
        elif name.startswith('assets/third-party/'):
            expected[name] = content
    for name in ['app-icon.png', 'developer-avatar.png']:
        expected['assets/flutter_assets/assets/' + name] = values['design/branding/' + name]
    return version, int(code), expected


def parse_tools(badging, resources, certificates):
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
    identity = re.search(r'string/build_source_identity\s+\(\) "([^"\r\n]+)"', resources)
    signers = re.findall(r'Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})', certificates)
    if not package or not identity or len(signers) != 1:
        raise ValueError('Missing package/source identity or ambiguous signing certificate.')
    return {'package': package[1], 'code': int(package[2]), 'version': package[3],
            'debuggable': bool(re.search(r'^application-debuggable\b', badging, re.M)),
            'sourceIdentity': identity[1], 'signerSha256': signers[0].lower()}


def inspect(path, tools):
    # apksigner's successful exit verifies the signature; its printed digest
    # alone would not establish that the ZIP is still correctly signed.
    info = parse_tools(command(tools / 'aapt2.exe', 'dump', 'badging', path),
                       command(tools / 'aapt2.exe', 'dump', 'resources', path),
                       command(tools / 'apksigner.bat', 'verify', '--verbose', '--print-certs', path))
    info.update(file=path.name, bytes=path.stat().st_size, sha256=file_digest(path))
    return info


def engine_jar(flutter_sdk, caches, abi, mode):
    revision = (flutter_sdk / 'bin/internal/engine.version').read_text().strip()
    exact(revision, 40)
    artifact = abi.replace('-', '_') + '_' + mode
    for cache in caches:
        folder = cache / 'caches/modules-2/files-2.1/io.flutter' / artifact / ('1.0.0-' + revision)
        jars = list(folder.glob('*/' + artifact + '-1.0.0-' + revision + '.jar'))
        if jars:
            for jar in jars:
                # Gradle renders SHA-1 as an integer, omitting leading zeroes.
                if (file_digest(jar, 'sha1').lstrip('0') or '0') != jar.parent.name:
                    raise ValueError('Cached Flutter engine JAR integrity mismatch.')
            return jars[0]
    raise ValueError('Pinned Flutter engine JAR absent; provide its Gradle cache.')


def executable_fingerprint(data):
    # Android strips debug symbols and rewrites ELF section headers when
    # packaging. Compare executable load segments, which preserve engine code.
    if len(data) < 64 or data[:4] != b'\x7fELF' or data[4] not in (1, 2) or data[5] not in (1, 2):
        raise ValueError('Invalid Flutter ELF engine.')
    order = '<' if data[5] == 1 else '>'
    wide = data[4] == 2
    offset = struct.unpack_from(order + ('Q' if wide else 'I'), data, 32 if wide else 28)[0]
    size, count = struct.unpack_from(order + 'HH', data, 54 if wide else 42)
    layout = order + ('IIQQQQQQ' if wide else 'IIIIIIII')
    if size < struct.calcsize(layout) or count > 128:
        raise ValueError('Unsupported ELF program headers.')
    segments = []
    for index in range(count):
        values = struct.unpack_from(layout, data, offset + size * index)
        kind = values[0]
        flags, start, address, length, memory = ((values[1], values[2], values[3], values[5], values[6])
            if wide else (values[6], values[1], values[2], values[4], values[5]))
        if kind == 1 and flags & 1:
            if not length or start + length > len(data):
                raise ValueError('Truncated executable engine segment.')
            # Some Android engine LOAD segments include the ELF header itself;
            # stripping rewrites its section-table pointer/count, not code.
            code_start = max(start, 64 if wide else 52)
            segments.append((flags, address, length, memory, hashlib.sha256(data[code_start:start+length]).hexdigest()))
    if not segments:
        raise ValueError('Flutter engine lacks executable load segments.')
    return data[18:20], segments


def check_zip(path, expected, mode, flutter_sdk, caches):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(set(names)) != len(names) or archive.testzip() is not None:
            raise ValueError('Duplicate or damaged APK ZIP entries.')
        forbidden = re.compile(r'(synthetic-media|fixture\.json|\.m3u8$|\.ts$|\.har$|\.keystore$|\.jks$|(?:schedule|classroom-library|classroom-progress|classroom-links)-v\d+\.json)', re.I)
        if any(forbidden.search(name) for name in names):
            raise ValueError('Test media, private cache or signing material found in APK.')
        for name, value in expected.items():
            if name not in names or archive.read(name) != value:
                raise ValueError('Public script/artwork/license does not match source: ' + name)
        kernel = 'assets/flutter_assets/kernel_blob.bin' in names
        if kernel != (mode == 'debug'):
            raise ValueError('Flutter kernel/AOT mode mismatch.')
        abis = sorted({name.split('/')[1] for name in names if re.fullmatch(r'lib/[^/]+/libflutter\.so', name)})
        if not abis:
            raise ValueError('No Flutter engine found.')
        for abi in abis:
            if abi not in ('arm64-v8a', 'armeabi-v7a', 'x86_64'):
                raise ValueError('Unsupported Flutter ABI.')
            jar = engine_jar(flutter_sdk, caches, abi, mode)
            with zipfile.ZipFile(jar) as engine:
                # Profile also has AOT and may be non-debuggable: check the
                # exact pinned engine, rather than accepting profile as release.
                if executable_fingerprint(archive.read(f'lib/{abi}/libflutter.so')) != executable_fingerprint(engine.read(f'lib/{abi}/libflutter.so')):
                    raise ValueError('Flutter engine does not match requested build mode.')
            if mode == 'release' and f'lib/{abi}/libapp.so' not in names:
                raise ValueError('Release lacks application AOT.')
    return abis


def verify_ci(run, jobs, source):
    if (run.get('head_sha') != source or run.get('status') != 'completed' or
            run.get('conclusion') != 'success' or run.get('repository', {}).get('full_name') != REPOSITORY):
        raise ValueError('CI must succeed for the exact source in this repository.')
    if jobs.get('total_count', 0) > 100:
        raise ValueError('CI job response incomplete.')
    passed = {job['name'] for job in jobs.get('jobs', []) if job.get('conclusion') == 'success'}
    if not {'quality', 'dual-preview'} <= passed:
        raise ValueError('CI needs successful full quality and dual-preview jobs.')
    return {'id': run['id'], 'sourceSha': source, 'url': run['html_url'], 'conclusion': 'success'}


def fetch_ci(run_id, source):
    if run_id < 1:
        raise ValueError('A successful CI run ID is required for release verification.')
    def get(suffix):
        request = Request(f'https://api.github.com/repos/{REPOSITORY}/actions/runs/{run_id}{suffix}',
                          headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'campus-artifact-check'})
        with urlopen(request, timeout=20) as response:
            data = response.read(2 * 1024 * 1024 + 1)
        if len(data) > 2 * 1024 * 1024:
            raise ValueError('CI response exceeds verification limit.')
        return json.loads(data)
    return verify_ci(get(''), get('/jobs?per_page=100'), source)


def verify_pair(infos, source, version, code, signer=None, kind='preview'):
    if kind == 'release' and signer is None:
        raise ValueError('Release verification requires the trusted certificate digest.')
    if signer is not None:
        exact(signer, 64)
    for mode, info in infos.items():
        if info['package'] != PACKAGE or (info['version'], info['code']) != (version, code):
            raise ValueError('Wrong package/version, possibly an isolated instrumentation APK.')
        if info['debuggable'] != (mode == 'debug'):
            raise ValueError('Android debug flag mismatch.')
        allowed = [source] if kind == 'release' else [source, source + '-modified']
        if info['sourceIdentity'] not in allowed:
            raise ValueError('Wrong or dirty embedded source identity.')
        if signer is not None and info['signerSha256'] != signer:
            raise ValueError('Certificate differs from trusted upgrade signer.')
    if infos['debug']['sourceIdentity'] != infos['release']['sourceIdentity'] or infos['debug']['signerSha256'] != infos['release']['signerSha256']:
        raise ValueError('Dual APKs differ in source identity or signer.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', choices=('verify', 'ci'), default='verify')
    parser.add_argument('--debug', type=Path)
    parser.add_argument('--release', type=Path)
    parser.add_argument('--source', required=True)
    parser.add_argument('--kind', choices=('preview', 'release'), default='preview')
    parser.add_argument('--signer-sha256')
    parser.add_argument('--ci-run-id', type=int, default=0)
    parser.add_argument('--build-tools', type=Path)
    parser.add_argument('--flutter-sdk', type=Path)
    parser.add_argument('--gradle-cache', action='append', type=Path,
                        help='Repeat if historical APKs used different Gradle caches.')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    exact(args.source, 40)
    if args.action == 'ci':
        print(json.dumps(fetch_ci(args.ci_run_id, args.source), indent=2))
        return
    if any(value is None for value in [args.debug, args.release, args.build_tools, args.flutter_sdk, args.output]):
        parser.error('Verification needs --debug, --release, --build-tools, --flutter-sdk and --output.')
    if args.kind == 'release' and not args.signer_sha256:
        raise ValueError('Release verification requires the trusted certificate digest.')
    if command('git', '-C', args.flutter_sdk, 'rev-parse', 'HEAD').strip() != FLUTTER_SHA:
        raise ValueError('Flutter SDK revision mismatch.')
    if args.output.exists():
        raise ValueError('Verification output already exists; use a fresh result file.')
    version, code, expected = source_assets(args.source)
    ci = fetch_ci(args.ci_run_id, args.source) if args.kind == 'release' else None
    infos = {mode: inspect(path, args.build_tools) for mode, path in [('debug', args.debug), ('release', args.release)]}
    verify_pair(infos, args.source, version, code, args.signer_sha256, args.kind)
    for mode, path in [('debug', args.debug), ('release', args.release)]:
        caches = args.gradle_cache or [Path(os.environ.get('GRADLE_USER_HOME', Path.home() / '.gradle'))]
        infos[mode]['abis'] = check_zip(path, expected, mode, args.flutter_sdk, caches)
    report = {'schema': 1, 'scope': 'dual-apk-verification', 'kind': args.kind, 'sourceSha': args.source,
              'version': version, 'code': code, 'flutterSha': FLUTTER_SHA, 'artifacts': infos, 'ci': ci,
              'limits': 'No install, runtime diagnostic UI, R8 XLS, native media or school acceptance is performed.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('Verified dual APK identity, signatures, engines, public assets and ZIP integrity: ' + str(args.output))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, struct.error, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print('APK verification failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
