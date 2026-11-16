"""Synthetic regression tests for selection, Git scope and failure propagation."""
from contextlib import redirect_stdout, redirect_stderr
from io import StringIO
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from scripts import check
from scripts.check_plan import (MODULES, DIRECT_TESTS, affected_tests,
                                flutter_files, make_plan, validate_inventory)

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/checks/tooling'


def synthetic_directory():
    WORK.mkdir(parents=True, exist_ok=True)
    temporary = tempfile.TemporaryDirectory(prefix='synthetic-', dir=WORK)
    if not Path(temporary.name).resolve().is_relative_to(WORK.resolve()):
        raise ValueError('Synthetic test directory escaped build/checks/tooling')
    return temporary


class SelectionTest(unittest.TestCase):
    def test_registry_covers_every_current_test(self):
        validate_inventory(ROOT)

    def test_legacy_keeps_all_offline_suites_without_flutter(self):
        plan = make_plan(ROOT, legacy=True)
        self.assertEqual(len(plan.java), 5)
        self.assertEqual(len(plan.node), 9)
        self.assertTrue(plan.icons and plan.examples)
        self.assertFalse(plan.flutter or plan.direct or plan.analyze)

    def test_player_is_independent_of_xls_and_directory(self):
        plan = make_plan(ROOT, ['player'])
        self.assertEqual(plan.java, ['ClassroomMediaTest'])
        self.assertEqual(plan.node, ['classroom-player-test.cjs'])
        self.assertNotIn('test/classroom_api_reader_test.dart', plan.flutter)
        self.assertEqual(plan.flutter, flutter_files(['player']))
        self.assertIn('test/classroom_preparation_test.dart', plan.flutter)

    def test_combined_modules_deduplicate_shared_tests(self):
        plan = make_plan(ROOT, ['player', 'storage'])
        self.assertEqual(plan.flutter.count('test/classroom_playback_progress_test.dart'), 1)

    def test_direct_configuration_is_explicit_and_all_includes_it(self):
        self.assertFalse(make_plan(ROOT, ['classroom']).direct)
        self.assertEqual(make_plan(ROOT, ['classroom'], direct=True).direct, list(DIRECT_TESTS))
        all_plan = make_plan(ROOT, all_checks=True)
        self.assertEqual(set(all_plan.flutter), set(flutter_files(MODULES)))
        self.assertEqual(all_plan.direct, list(DIRECT_TESTS))
        self.assertNotIn('test/preview_capture_test.dart', all_plan.flutter)

    def test_document_only_changes_do_not_require_sdk(self):
        plan = make_plan(ROOT, changed=['README.md', 'docs/TESTING.md'])
        self.assertTrue(plan.docs)
        self.assertFalse(plan.java or plan.node or plan.flutter or plan.analyze)

    def test_empty_diff_and_tooling_do_not_invoke_flutter(self):
        plan = make_plan(ROOT, changed=[])
        self.assertFalse(plan.flutter or plan.direct or plan.analyze or plan.java or plan.node)
        plan = make_plan(ROOT, ['tooling'])
        self.assertTrue(plan.tooling)
        self.assertFalse(plan.flutter or plan.analyze)

    def test_transitive_imports_cycles_and_test_helpers(self):
        graph = {'mobile/lib/model.dart': set(),
                 'mobile/lib/service.dart': {'mobile/lib/model.dart', 'mobile/lib/loop.dart'},
                 'mobile/lib/loop.dart': {'mobile/lib/service.dart'},
                 'mobile/test/helper.dart': {'mobile/lib/service.dart'},
                 'mobile/test/model_test.dart': {'mobile/test/helper.dart'},
                 'mobile/test/other_test.dart': set()}
        self.assertEqual(affected_tests(graph, ['mobile/lib/model.dart']), {'test/model_test.dart'})

    def test_changed_source_selects_consumer_and_enabled_direct_tests(self):
        for path in ['mobile/lib/platform/classroom_api_reader.dart',
                     'assets/recording-api.cjs']:
            with self.subTest(path=path):
                plan = make_plan(ROOT, changed=[path])
                self.assertEqual(plan.modules, ['classroom'] if path.startswith('assets/') else [])
                self.assertIn('test/classroom_api_reader_test.dart', plan.flutter)
                self.assertIn('test/classroom_direct_import_test.dart', plan.flutter)
                self.assertEqual(plan.direct, list(DIRECT_TESTS))

    def test_native_and_deleted_sources_have_safe_fallback(self):
        for name in ['new/unmapped.xyz', 'mobile/lib/deleted.dart',
                     'src/cn/bucm/campusprobe/NewMediaHelper.java',
                     'mobile/android/app/build.gradle.kts']:
            with self.subTest(path=name):
                plan = make_plan(ROOT, changed=[name])
                self.assertEqual(set(plan.modules), set(MODULES))
                self.assertTrue(plan.reasons)
        plan = make_plan(ROOT, changed=['mobile/android/app/build.gradle.kts'])
        self.assertTrue(plan.required_manual)

    def test_unknown_test_cannot_silently_disappear(self):
        with patch('scripts.check_plan.Path.rglob', return_value=[]):
            with self.assertRaisesRegex(ValueError, 'Update Flutter module registry'):
                validate_inventory(ROOT)

    def test_dry_run_never_executes_or_writes_reports(self):
        with patch.object(check, 'execute') as execute, patch.object(Path, 'write_text') as write:
            with redirect_stdout(StringIO()):
                self.assertEqual(check.main(['--module', 'docs', '--dry-run']), 0)
            execute.assert_not_called()
            write.assert_not_called()

    def test_failure_exit_code_and_report_prevent_false_pass(self):
        calls = []
        def fail(plan, runner, flutter):
            runner.command('synthetic-failure', ['synthetic-command'])
            calls.append('should-not-continue')
        with patch.object(check, 'execute', side_effect=fail):
            with patch.object(check.subprocess, 'run', side_effect=subprocess.CalledProcessError(7, ['synthetic-command'])):
                with patch.object(Path, 'write_text') as write:
                    with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
                        self.assertEqual(check.main(['--module', 'docs']), 7)
                    import json
                    report = json.loads(write.call_args.args[0])
                    self.assertEqual(report['status'], 'failed')
                    self.assertEqual(report['steps'][0]['exitCode'], 7)
        self.assertFalse(calls)

    def test_document_checker_detects_missing_file(self):
        with synthetic_directory() as folder:
            root = Path(folder)
            (root / 'README.md').write_text('[valid](other.md) [missing](lost.md)', encoding='utf-8')
            (root / 'other.md').write_text('synthetic', encoding='utf-8')
            with patch.object(check.subprocess, 'check_output', side_effect=[b'README.md\0', b'']):
                with self.assertRaisesRegex(ValueError, 'lost.md'):
                    check.check_docs(root)


class GitScopeTest(unittest.TestCase):
    def test_merge_base_rename_deletion_local_and_untracked(self):
        # A disposable synthetic repository; never change the real working tree.
        with synthetic_directory() as folder:
            root = Path(folder)
            def git(*args):
                return subprocess.check_output(['git', '-c', 'user.name=Synthetic',
                    '-c', 'user.email=synthetic@example.invalid', *args], cwd=root, stderr=subprocess.STDOUT)
            git('init', '-q')
            (root / 'removed.dart').write_text('synthetic', encoding='utf-8')
            (root / 'local.dart').write_text('before', encoding='utf-8')
            (root / '.gitignore').write_text('ignored.txt\n', encoding='utf-8')
            git('add', '.')
            git('commit', '-qm', 'synthetic baseline')
            base = git('rev-parse', 'HEAD').decode().strip()
            (root / 'removed.dart').rename(root / 'renamed.dart')
            git('add', '-A')
            git('commit', '-qm', 'synthetic rename')
            head = git('rev-parse', 'HEAD').decode().strip()
            original = git('branch', '--show-current').decode().strip()
            git('checkout', '-qb', 'comparison', base)
            (root / 'base-only.txt').write_text('synthetic', encoding='utf-8')
            git('add', '.')
            git('commit', '-qm', 'synthetic divergent base')
            git('checkout', '-q', original)
            self.assertEqual(git('rev-parse', 'HEAD').decode().strip(), head)
            (root / 'local.dart').write_text('after', encoding='utf-8')
            (root / 'staged.dart').write_text('synthetic', encoding='utf-8')
            git('add', 'staged.dart')
            (root / 'untracked.dart').write_text('synthetic', encoding='utf-8')
            (root / 'ignored.txt').write_text('synthetic', encoding='utf-8')
            paths, ancestor = check.changed_files(root, 'comparison')
            self.assertEqual(set(paths), {'removed.dart', 'renamed.dart', 'local.dart', 'staged.dart', 'untracked.dart'})
            self.assertEqual(ancestor, base)
            with self.assertRaises(subprocess.CalledProcessError):
                check.changed_files(root, '--not-a-real-ref')


if __name__ == '__main__':
    unittest.main()
