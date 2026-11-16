"""Pin CI scope to one source/base SHA; reuse the local check planner/runner."""
import argparse
from dataclasses import asdict
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import check
from scripts.check_plan import Plan, make_plan


def sha(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{40}', value):
        raise ValueError('Expected an exact source/base SHA.')
    return value


def policy(event_name, event, source_sha):
    source_sha = sha(source_sha)
    if event_name == 'pull_request':
        pr = event['pull_request']
        return {'sourceSha': sha(pr['head']['sha']), 'base': sha(pr['base']['sha']),
                'mode': 'changed', 'preview': False}
    if event_name not in ('push', 'workflow_dispatch'):
        raise ValueError('Unsupported CI event.')
    ref = event.get('ref', '')
    if not (ref == 'refs/heads/main' or ref.startswith('refs/heads/codex/')):
        raise ValueError('CI accepts main/codex branches, not tags or unknown refs.')
    mode = 'full' if ref == 'refs/heads/main' or ref.startswith('refs/heads/codex/release/') else 'changed'
    preview = mode == 'full'
    if event_name == 'workflow_dispatch':
        profile = event.get('inputs', {}).get('profile', 'changed')
        if profile not in ('changed', 'full', 'preview'):
            raise ValueError('Unknown dispatch profile.')
        mode, preview = ('changed' if profile == 'changed' else 'full'), profile == 'preview'
    # Compare the whole branch, not only the last push: prior checks may have
    # been cancelled by concurrency, including the first push of a new branch.
    return {'sourceSha': source_sha, 'base': 'origin/main' if mode == 'changed' else None,
            'mode': mode, 'preview': preview}


def head(root):
    return sha(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip())


def materialize(root, selected):
    if head(root) != selected['sourceSha']:
        raise ValueError('Checkout does not match the requested source SHA.')
    if selected['mode'] == 'changed':
        base = subprocess.check_output(['git', 'rev-parse', '--verify', '--end-of-options',
                                        selected['base'] + '^{commit}'], cwd=root, text=True).strip()
        selected = {**selected, 'base': sha(base)}
        paths, _ = check.changed_files(root, selected['base'])
        plan = make_plan(root, changed=paths)
    else:
        plan = make_plan(root, all_checks=True)
    return {'schema': 1, 'scope': 'ci-host-selection', **selected,
            'needsFlutter': bool(plan.analyze or plan.flutter or plan.direct),
            'needsJava': bool(plan.java), 'needsNode': bool(plan.node),
            'needsDeps': 'ExportTest' in plan.java, 'checks': asdict(plan)}


def run(root, document):
    if document['schema'] != 1 or document['scope'] != 'ci-host-selection':
        raise ValueError('Unsupported CI plan.')
    if head(root) != sha(document['sourceSha']):
        raise ValueError('Source changed since CI planning.')
    # pub get may normalize the lock's source URL after planning. Execute the
    # pinned selection rather than treating that CI-only edit as a new change.
    runner = check.Runner()
    report = {'schema': 1, 'scope': 'synthetic-host-checks', 'status': 'failed',
              'sourceSha': document['sourceSha'], 'baseSha': document['base'],
              'plan': document['checks']}
    started = time.monotonic()
    try:
        flutter = shutil.which('flutter') or str(root / 'build/toolchain/flutter/bin/flutter.bat')
        check.execute(Plan(**document['checks']), runner, flutter)
        report['status'] = 'passed'
        return 0
    except subprocess.CalledProcessError as error:
        return error.returncode
    finally:
        report.update(steps=runner.results, seconds=round(time.monotonic() - started, 3))
        folder = root / 'build/checks'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'ci-report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'run'))
    args = parser.parse_args()
    path = ROOT / 'build/ci-plan.json'
    if args.action == 'run':
        return run(ROOT, json.loads(path.read_text(encoding='utf-8')))
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text(encoding='utf-8'))
    event['ref'] = os.environ['GITHUB_REF']
    selected = policy(os.environ['GITHUB_EVENT_NAME'], event, os.environ['GITHUB_SHA'])
    document = materialize(ROOT, selected)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(document, indent=2))
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            for name, value in {'sha': document['sourceSha'], 'preview': document['preview'],
                                'flutter': document['needsFlutter'], 'java': document['needsJava'],
                                'node': document['needsNode'], 'deps': document['needsDeps']}.items():
                output.write(f'{name}={str(value).lower()}\n')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
