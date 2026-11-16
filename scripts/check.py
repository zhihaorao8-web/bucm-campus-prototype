"""Select and run local synthetic checks. No arguments retain legacy offline checks."""
import argparse
from dataclasses import asdict
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.check_plan import DEBUG_FLOWS, JAVA_SOURCES, MODULES, make_flow_plan, make_plan


def changed_files(root, base):
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root,
                                       stderr=subprocess.PIPE).decode('utf-8').strip()
    # Resolve a commit first: user-supplied values cannot become Git options.
    commit = git('rev-parse', '--verify', '--end-of-options', base + '^{commit}')
    ancestor = git('merge-base', commit, 'HEAD')
    def paths(*args):
        value = subprocess.check_output(['git', *args], cwd=root)
        return {p.decode('utf-8') for p in value.split(b'\0') if p}
    # No rename collapsing: both the removed source and new target are considered.
    result = paths('diff', '--name-only', '--no-renames', '-z', ancestor, 'HEAD', '--')
    result |= paths('diff', '--name-only', '--no-renames', '-z', 'HEAD', '--')
    result |= paths('ls-files', '--others', '--exclude-standard', '-z')
    return sorted(result), ancestor


def check_docs(root=ROOT):
    # Only repository documents; never traverse ignored captures/caches.
    tracked = subprocess.check_output(['git', 'ls-files', '-z', '--', '*.md'], cwd=root)
    untracked = subprocess.check_output(
        ['git', 'ls-files', '--others', '--exclude-standard', '-z', '--', '*.md'], cwd=root)
    paths = sorted(set(p.decode('utf-8') for p in (tracked + untracked).split(b'\0') if p))
    broken, count = [], 0
    for name in paths:
        path = root / name
        if not path.exists():
            continue  # A staged/unstaged deletion is not a document to read.
        text = path.read_text(encoding='utf-8-sig')
        for match in re.finditer(r'\[[^\]]*\]\((<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)', text):
            target = match.group(1).strip('<>').split('#')[0]
            if not target or re.match(r'[a-zA-Z][\w+.-]*:', target) or target.startswith('/'):
                continue
            count += 1
            if not (path.parent / unquote(target)).exists():
                broken.append(f'{name}:{text.count(chr(10), 0, match.start()) + 1}: {target}')
    if broken:
        raise ValueError('Missing Markdown targets:\n' + '\n'.join(broken))
    print(f'Markdown: {count} local file targets; anchors and remote URLs not checked.', flush=True)


def check_examples():
    for path in (ROOT / 'examples').glob('*.json'):
        if json.loads(path.read_text(encoding='utf-8')).get('synthetic') is not True:
            raise ValueError('Examples must be explicitly synthetic: ' + path.name)


def flutter_commands(plan, executable):
    commands = []
    if plan.analyze:
        commands.append(('flutter-analyze', [executable, 'analyze', '--no-pub']))
    if plan.flutter:
        commands.append(('flutter-default', [executable, 'test', '--no-pub', *plan.flutter]))
    if plan.direct:
        commands.append(('flutter-direct', [executable, 'test', '--no-pub',
                         '--dart-define=CAMPUS_DIRECT_CATALOG=true', *plan.direct]))
    return commands


class Runner:
    def __init__(self):
        self.results = []

    def step(self, name, operation):
        print(f'== {name} ==', flush=True)
        started = time.monotonic()
        result = {'name': name, 'exitCode': 0}
        try:
            operation()
        except BaseException as error:
            result['exitCode'] = (error.returncode if isinstance(error, subprocess.CalledProcessError)
                                  else error.code if isinstance(error, SystemExit) and isinstance(error.code, int)
                                  else 130 if isinstance(error, KeyboardInterrupt) else 1)
            if result['exitCode'] == 0:
                result['exitCode'] = 1
            raise
        finally:
            result['seconds'] = round(time.monotonic() - started, 3)
            self.results.append(result)

    def command(self, name, command, cwd=ROOT):
        self.step(name, lambda: subprocess.run(command, cwd=cwd, check=True))


def execute(plan, runner, flutter):
    if plan.docs:
        runner.step('docs', check_docs)
    if plan.tooling:
        runner.command('tooling', [sys.executable, '-m', 'unittest', 'discover',
                                  '-s', 'tests', '-p', 'test_*.py', '-v'])
    if plan.icons:
        from scripts.iconmcp_assets import check_assets
        runner.step('icons', check_assets)
    if plan.examples:
        runner.step('examples', check_examples)
    if plan.java:
        from scripts.java_tools import EXE, java_tools
        java = java_tools()
        sources = sorted({name for test in plan.java for name in JAVA_SOURCES[test]})
        deps = ''
        if 'ExportTest' in plan.java:
            from scripts.dependencies import dependencies
            deps = os.pathsep.join(str(p) for p in dependencies())
        work = ROOT / 'build/checks'
        work.mkdir(parents=True, exist_ok=True)
        classes = Path(tempfile.mkdtemp(prefix='java-', dir=work)).resolve()
        if not classes.is_relative_to(work.resolve()):
            raise ValueError('Java check output escaped build/checks')
        command = [str(java / ('javac' + EXE)), '--release', '8', '-encoding', 'UTF-8']
        if deps:
            command += ['-classpath', deps]
        command += ['-d', str(classes)]
        command += [str(ROOT / 'src/cn/bucm/campusprobe' / (name + '.java')) for name in sources]
        command += [str(ROOT / 'tests' / (test + '.java')) for test in plan.java]
        if 'ExportTest' in plan.java:
            command.append(str(ROOT / 'tests/ReleaseFixture.java'))
        runner.command('java-compile', command)
        for test in plan.java:
            runner.command('java-' + test, [str(java / ('java' + EXE)), '-cp',
                           str(classes) + (os.pathsep + deps if deps else ''), test])
    if plan.node:
        node = shutil.which('node')
        if not node:
            raise ValueError('Node.js is required for the selected synthetic checks.')
        for test in plan.node:
            runner.command('node-' + test, [node, str(ROOT / 'tests' / test)])
    commands = flutter_commands(plan, flutter)
    if commands and not (Path(flutter).is_file() or shutil.which(flutter)):
        raise ValueError('Flutter SDK not found; use --flutter PATH or prepare the pinned SDK.')
    for name, command in commands:
        runner.command(name, command, ROOT / 'mobile')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    select = parser.add_mutually_exclusive_group()
    select.add_argument('--module', choices=MODULES, action='append', help='Repeat to combine modules.')
    select.add_argument('--flow', choices=DEBUG_FLOWS, help='A reusable synthetic debugging chain.')
    select.add_argument('--changed', action='store_true', help='Merge-base diff plus local/untracked files.')
    select.add_argument('--all', action='store_true', help='All host checks, Flutter analysis/default/direct tests.')
    parser.add_argument('--base', default='origin/main', help='Git base for --changed (default: origin/main).')
    parser.add_argument('--dry-run', action='store_true', help='Print plan only; no SDK or outputs required.')
    parser.add_argument('--direct-catalog', action='store_true', help='Also run the enabled direct-catalog suite.')
    parser.add_argument('--flutter', help='Flutter executable; defaults to PATH or the pinned local SDK.')
    args = parser.parse_args(argv)
    legacy = not (args.module or args.flow or args.changed or args.all)
    if legacy and args.direct_catalog:
        parser.error('--direct-catalog requires --module, --flow, --changed or --all')
    if args.base != 'origin/main' and not args.changed:
        parser.error('--base requires --changed')
    runner = Runner()
    started = time.monotonic()
    report = {'schema': 1, 'scope': 'synthetic-host-checks', 'status': 'failed'}
    try:
        paths, ancestor = changed_files(ROOT, args.base) if args.changed else (None, None)
        plan = (make_flow_plan(ROOT, args.flow, direct=args.direct_catalog) if args.flow else
                make_plan(ROOT, modules=args.module or (), changed=paths, legacy=legacy,
                          direct=args.direct_catalog, all_checks=args.all))
        flutter = args.flutter or shutil.which('flutter') or str(ROOT / 'build/toolchain/flutter/bin' / ('flutter.bat' if os.name == 'nt' else 'flutter'))
        report.update({'legacy': legacy, 'flow': args.flow, 'mergeBase': ancestor, 'changed': paths, 'plan': asdict(plan)})
        print(json.dumps({'legacy': legacy, 'changed': paths, 'mergeBase': ancestor,
                          'plan': asdict(plan), 'flutterCommands': flutter_commands(plan, flutter)},
                         ensure_ascii=False, indent=2), flush=True)
        if args.dry_run:
            return 0
        execute(plan, runner, flutter)
        report['status'] = 'passed'
        print('Selected host checks passed; device/school acceptance is separate.', flush=True)
        return 0
    except (Exception, SystemExit) as error:
        print(str(error), file=sys.stderr, flush=True)
        return error.returncode if isinstance(error, subprocess.CalledProcessError) else 1
    except KeyboardInterrupt:
        print('Checks interrupted.', file=sys.stderr, flush=True)
        return 130
    finally:
        if not args.dry_run:
            report['steps'] = runner.results
            report['seconds'] = round(time.monotonic() - started, 3)
            folder = ROOT / 'build/checks'
            folder.mkdir(parents=True, exist_ok=True)
            path = folder / ('report-' + uuid.uuid4().hex + '.json')
            path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            print('Check report: ' + str(path), flush=True)


if __name__ == '__main__':
    sys.exit(main())
