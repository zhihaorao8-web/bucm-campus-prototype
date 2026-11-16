"""CI event/SHA/selection checks without SDKs or external services."""
from dataclasses import asdict
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
from scripts import ci_plan
from scripts.check_plan import Plan
from test_check import ROOT, synthetic_directory

A, B = 'a' * 40, 'b' * 40


class CiPlanTest(unittest.TestCase):
    def test_branch_roles_and_new_push_do_not_depend_on_before(self):
        for branch, mode, preview in [('main', 'full', True), ('codex/release/0.4', 'full', True),
                                      ('codex/fix-import', 'changed', False)]:
            with self.subTest(branch=branch):
                selected = ci_plan.policy('push', {'ref': 'refs/heads/' + branch, 'before': '0' * 40}, A)
                self.assertEqual((selected['mode'], selected['preview']), (mode, preview))
                self.assertEqual(selected['base'], 'origin/main' if mode == 'changed' else None)

    def test_pr_pins_head_and_base_not_merge_commit_and_never_builds(self):
        selected = ci_plan.policy('pull_request', {'pull_request': {'head': {'sha': A}, 'base': {'sha': B}}}, 'c' * 40)
        self.assertEqual(selected, {'sourceSha': A, 'base': B, 'mode': 'changed', 'preview': False})

    def test_dispatch_profiles_and_invalid_events_fail_closed(self):
        for profile in ['changed', 'full', 'preview']:
            selected = ci_plan.policy('workflow_dispatch', {'ref': 'refs/heads/codex/test', 'inputs': {'profile': profile}}, A)
            self.assertEqual(selected['preview'], profile == 'preview')
        for event, body in [('push', {'ref': 'refs/tags/v0.3'}), ('schedule', {}),
                            ('workflow_dispatch', {'ref': 'refs/heads/main', 'inputs': {'profile': 'publish'}})]:
            with self.assertRaises(ValueError):
                ci_plan.policy(event, body, A)
        with self.assertRaises(ValueError):
            ci_plan.policy('push', {'ref': 'refs/heads/main'}, '--bad')

    def test_docs_only_plan_needs_no_sdk_or_build_and_pins_base(self):
        selected = {'sourceSha': A, 'base': 'origin/main', 'mode': 'changed', 'preview': False}
        with patch.object(ci_plan, 'head', return_value=A), patch.object(ci_plan.subprocess, 'check_output', return_value=B), \
                patch.object(ci_plan.check, 'changed_files', return_value=(['docs/TESTING.md'], B)):
            plan = ci_plan.materialize(ROOT, selected)
        self.assertEqual(plan['base'], B)
        self.assertTrue(plan['checks']['docs'])
        self.assertFalse(plan['needsFlutter'] or plan['needsJava'] or plan['needsNode'])

    def test_checkout_mismatch_cannot_run_checks(self):
        with patch.object(ci_plan, 'head', return_value=B):
            with self.assertRaises(ValueError):
                ci_plan.materialize(ROOT, {'sourceSha': A})
            with self.assertRaises(ValueError):
                ci_plan.run(ROOT, {'schema': 1, 'scope': 'ci-host-selection', 'sourceSha': A})

    def test_runner_failure_keeps_exit_code_and_failed_evidence(self):
        with synthetic_directory() as folder:
            def fail(plan, runner, flutter):
                runner.command('synthetic', ['synthetic-command'])
            with patch.object(ci_plan, 'head', return_value=A), patch.object(ci_plan.check, 'execute', side_effect=fail), \
                    patch.object(ci_plan.check.subprocess, 'run', side_effect=subprocess.CalledProcessError(7, ['synthetic-command'])):
                self.assertEqual(ci_plan.run(Path(folder), {'schema': 1, 'scope': 'ci-host-selection',
                    'sourceSha': A, 'base': B, 'checks': asdict(Plan())}), 7)
            report = json.loads((Path(folder) / 'build/checks/ci-report.json').read_text())
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(report['steps'][0]['exitCode'], 7)

    def test_run_uses_pinned_selection_even_after_ci_lock_normalization(self):
        with synthetic_directory() as folder:
            with patch.object(ci_plan, 'head', return_value=A), patch.object(ci_plan.check, 'execute') as execute, \
                    patch.object(ci_plan.check, 'changed_files') as rescan:
                result = ci_plan.run(Path(folder), {'schema': 1, 'scope': 'ci-host-selection',
                    'sourceSha': A, 'base': B, 'checks': asdict(Plan(docs=True))})
            self.assertEqual(result, 0)
            self.assertTrue(execute.call_args.args[0].docs)
            self.assertFalse(execute.call_args.args[0].flutter)
            rescan.assert_not_called()
            report = json.loads((Path(folder) / 'build/checks/ci-report.json').read_text())
            self.assertEqual(report['status'], 'passed')
