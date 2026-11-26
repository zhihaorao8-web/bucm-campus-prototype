"""Prepare public Flutter dependencies in a Paseo worktree."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
FLUTTER_REVISION = 'c197ca5199e9ee5661e865596c9c07294dfab51c'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-plan', action='store_true', help='Preview checks relative to origin/main.')
    args = parser.parse_args()

    source = Path(os.environ.get('PASEO_SOURCE_CHECKOUT_PATH') or ROOT).resolve()
    executable = 'flutter.bat' if os.name == 'nt' else 'flutter'
    bundled = source / 'build/toolchain/flutter/bin' / executable
    flutter = str(bundled) if bundled.is_file() else shutil.which(executable)
    if not flutter:
        raise SystemExit('Flutter 3.47.9 is required on PATH or in the source checkout; see docs/FLUTTER.md.')

    if args.check_plan:
        subprocess.run(
            [sys.executable, 'scripts/check.py', '--changed', '--base', 'origin/main', '--dry-run', '--flutter', flutter],
            cwd=ROOT,
            check=True,
        )
        return

    env = os.environ.copy()
    # Match the repository lockfile and keep Windows plugin sources on the worktree drive.
    env['PUB_HOSTED_URL'] = 'https://pub.flutter-io.cn'
    env.setdefault('FLUTTER_STORAGE_BASE_URL', 'https://storage.flutter-io.cn')
    source_cache = source / 'build/pub-cache'
    cache = source_cache if source_cache.is_dir() and source.drive == ROOT.drive else ROOT / 'build/pub-cache'
    env['PUB_CACHE'] = str(cache)

    version = subprocess.check_output([flutter, '--version', '--machine'], cwd=ROOT, env=env)
    revision = json.loads(version)['frameworkRevision']
    if revision != FLUTTER_REVISION:
        raise SystemExit(f'Flutter SDK revision {revision} does not match the required {FLUTTER_REVISION}.')

    subprocess.run([sys.executable, 'scripts/dependencies.py'], cwd=ROOT, check=True)
    subprocess.run([sys.executable, 'scripts/prepare_flutter.py'], cwd=ROOT, check=True)
    subprocess.run([flutter, 'pub', 'get', '--enforce-lockfile'], cwd=ROOT / 'mobile', env=env, check=True)


if __name__ == '__main__':
    main()
