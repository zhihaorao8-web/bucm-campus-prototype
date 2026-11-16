"""Flow scopes reuse registered tests/host guards without device side effects."""
from contextlib import redirect_stdout, redirect_stderr
from io import StringIO
import json
import unittest
from unittest.mock import patch
from scripts import check
from scripts.check_plan import DEBUG_FLOWS, DIRECT_TESTS, MODULES, flutter_files, make_flow_plan
from test_check import ROOT


class DebugFlowTest(unittest.TestCase):
    def test_all_flows_use_existing_tests_and_remain_narrow(self):
        registered = set(flutter_files(MODULES))
        for name in DEBUG_FLOWS:
            with self.subTest(flow=name):
                plan = make_flow_plan(ROOT, name)
                self.assertTrue(set(plan.flutter) < registered)
                self.assertEqual(len(plan.flutter), len(set(plan.flutter)))
                self.assertTrue(plan.analyze)
                self.assertEqual(bool(plan.direct), DEBUG_FLOWS[name]['direct'])

    def test_auth_chain_has_enabled_directory_recovery_without_xls(self):
        plan = make_flow_plan(ROOT, 'auth-recovery')
        self.assertFalse(plan.java)
        self.assertEqual(plan.direct, list(DIRECT_TESTS))
        self.assertIn('test/classroom_recovery_page_test.dart', plan.flutter)
        self.assertNotIn('test/classroom_player_test.dart', plan.flutter)

    def test_resume_chain_is_independent_of_directory_and_export(self):
        plan = make_flow_plan(ROOT, 'playback-resume')
        self.assertEqual(plan.java, ['ClassroomMediaTest'])
        self.assertFalse(plan.direct)
        self.assertNotIn('test/classroom_direct_import_test.dart', plan.flutter)
        self.assertIn('test/classroom_playback_progress_test.dart', plan.flutter)

    def test_cli_dry_run_never_executes_or_writes_and_modes_are_exclusive(self):
        output = StringIO()
        with patch.object(check, 'execute') as execute, patch.object(check.Path, 'write_text') as write, redirect_stdout(output):
            self.assertEqual(check.main(['--flow', 'storage-recovery', '--dry-run']), 0)
        execute.assert_not_called()
        write.assert_not_called()
        self.assertEqual(json.loads(output.getvalue())['plan']['modules'], ['storage'])
        with redirect_stderr(StringIO()), self.assertRaises(SystemExit) as result:
            check.main(['--flow', 'auth-recovery', '--all'])
        self.assertEqual(result.exception.code, 2)
