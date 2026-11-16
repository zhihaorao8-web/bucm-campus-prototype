"""Exercise the real PowerShell failure path in an isolated synthetic checkout."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest
from test_check import ROOT, synthetic_directory


@unittest.skipUnless(shutil.which('pwsh') and os.name == 'nt', 'Windows PowerShell build wrapper')
class BuildPreviewTest(unittest.TestCase):
    def exercise(self, exit_code):
        with synthetic_directory() as folder:
            root = Path(folder)
            (root / 'scripts').mkdir()
            shutil.copyfile(ROOT / 'scripts/build_flutter_previews.ps1', root / 'scripts/build_flutter_previews.ps1')
            (root / 'bin').mkdir()
            flutter = root / 'bin/flutter.cmd'
            flutter.write_text(f'@echo off\necho synthetic-build-output\necho synthetic-build-error 1>&2\nexit /b {exit_code}\n')
            tools = root / 'build-tools'
            tools.mkdir()
            for name in ['aapt2.exe', 'apksigner.bat']: (tools / name).touch()
            (root / 'AndroidManifest.xml').write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" android:versionName="0.3" android:versionCode="12"/>')
            (root / '.gitignore').write_text('/build/\n/mobile/build/\n')
            stale = root / 'mobile/build/app/outputs/flutter-apk/app-debug.apk'
            stale.parent.mkdir(parents=True)
            stale.write_bytes(b'synthetic stale output')
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL, text=True).strip()
            git('init')
            git('add', '.')
            git('-c', 'user.name=Synthetic', '-c', 'user.email=synthetic@example.invalid', 'commit', '-m', 'synthetic')
            result = subprocess.run(['pwsh', '-NoProfile', '-File', str(root / 'scripts/build_flutter_previews.ps1'),
                '-Flutter', str(flutter.relative_to(root)), '-ExpectedSourceSha', git('rev-parse', 'HEAD'), '-BuildTools', str(tools)],
                cwd=root, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
            self.assertFalse(stale.exists(), result.stdout + result.stderr)
            self.assertFalse(list((root / 'build').rglob('build-metadata.json')))
            logs = list((root / 'build/flutter-preview-logs').glob('*.log'))
            self.assertEqual(len(logs), 1, result.stdout + result.stderr)
            text = logs[0].read_text(encoding='utf-8-sig')
            self.assertIn('synthetic-build-output', text)
            self.assertIn('synthetic-build-error', text)
            return result

    def test_failed_native_command_preserves_exit_code_and_log(self):
        self.assertEqual(self.exercise(9).returncode, 9)

    def test_success_without_new_apk_cannot_reuse_stale_output(self):
        result = self.exercise(0)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing fresh debug APK', result.stderr)
