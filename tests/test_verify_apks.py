"""Synthetic ZIP/identity/CI rejection tests. No real courses or credentials."""
import hashlib
import struct
from pathlib import Path
import unittest
import zipfile
from scripts import verify_apks as verify
from test_check import synthetic_directory

SOURCE, SIGNER = 'a' * 40, 'b' * 64


def synthetic_elf(code=b'release-engine'):
    value = bytearray(256) + code
    value[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<Q', value, 32, 64)
    struct.pack_into('<HH', value, 54, 56, 1)
    struct.pack_into('<IIQQQQQQ', value, 64, 1, 5, 256, 4096, 4096, len(code), len(code), 4096)
    return bytes(value)


def pair():
    return {mode: {'package': verify.PACKAGE, 'version': '0.3', 'code': 12,
                   'sourceIdentity': SOURCE, 'signerSha256': SIGNER, 'debuggable': mode == 'debug'}
            for mode in ['debug', 'release']}


class ApkVerificationTest(unittest.TestCase):
    def test_source_signer_mode_and_isolated_package_fail_closed(self):
        verify.verify_pair(pair(), SOURCE, '0.3', 12, SIGNER, 'release')
        for field, value in [('package', verify.PACKAGE + '.mediatest'), ('version', '0.2'),
                             ('code', 11), ('sourceIdentity', SOURCE + '-modified'),
                             ('signerSha256', 'c' * 64), ('debuggable', True)]:
            with self.subTest(field=field):
                infos = pair()
                infos['release'][field] = value
                with self.assertRaises(ValueError):
                    verify.verify_pair(infos, SOURCE, '0.3', 12, SIGNER, 'release')
        with self.assertRaises(ValueError):
            verify.verify_pair(pair(), SOURCE, '0.3', 12, kind='release')

    def test_modified_preview_is_explicit_and_both_apks_must_match(self):
        infos = pair()
        for info in infos.values():
            info['sourceIdentity'] += '-modified'
        verify.verify_pair(infos, SOURCE, '0.3', 12)
        infos['debug']['sourceIdentity'] = SOURCE
        with self.assertRaises(ValueError):
            verify.verify_pair(infos, SOURCE, '0.3', 12)

    def test_tool_output_requires_identity_and_exactly_one_signer(self):
        package = "package: name='cn.bucm.campus_schedule' versionCode='12' versionName='0.3'\napplication-debuggable"
        resources = f'resource string/build_source_identity\n  () "{SOURCE}"'
        certificate = 'Signer #1 certificate SHA-256 digest: ' + SIGNER
        self.assertTrue(verify.parse_tools(package, resources, certificate)['debuggable'])
        for output in ['', certificate + '\n' + certificate]:
            with self.assertRaises(ValueError):
                verify.parse_tools(package, resources, output)
        with self.assertRaises(ValueError):
            verify.parse_tools(package, '', certificate)

    def test_ci_requires_exact_sha_success_and_full_preview_jobs(self):
        run = {'id': 123, 'head_sha': SOURCE, 'status': 'completed', 'conclusion': 'success',
               'repository': {'full_name': verify.REPOSITORY}, 'html_url': 'https://github.com/synthetic'}
        jobs = {'total_count': 2, 'jobs': [{'name': name, 'conclusion': 'success'} for name in ['quality', 'dual-preview']]}
        self.assertEqual(verify.verify_ci(run, jobs, SOURCE)['id'], 123)
        for change in [{'head_sha': 'c' * 40}, {'conclusion': 'failure'}, {'status': 'in_progress'}]:
            with self.assertRaises(ValueError):
                verify.verify_ci({**run, **change}, jobs, SOURCE)
        for invalid in [{'total_count': 101}, {'jobs': [{'name': 'quality', 'conclusion': 'success'}]}]:
            with self.assertRaises(ValueError):
                verify.verify_ci(run, invalid, SOURCE)

    def test_zip_rejects_test_payload_changed_assets_and_profile_engine(self):
        with synthetic_directory() as folder:
            folder = Path(folder)
            apk = folder / 'synthetic.apk'
            (folder / 'bin/internal').mkdir(parents=True)
            (folder / 'bin/internal/engine.version').write_text(SOURCE)
            engine_dir = folder / 'caches/modules-2/files-2.1/io.flutter/arm64_v8a_release' / ('1.0.0-' + SOURCE)
            engine_dir.mkdir(parents=True)
            jar_path = engine_dir / 'synthetic.jar'
            with zipfile.ZipFile(jar_path, 'w') as jar:
                jar.writestr('lib/arm64-v8a/libflutter.so', synthetic_elf())
            hashed = engine_dir / hashlib.sha1(jar_path.read_bytes()).hexdigest().lstrip('0')
            hashed.mkdir()
            jar_path.rename(hashed / ('arm64_v8a_release-1.0.0-' + SOURCE + '.jar'))
            entries = {'assets/public.js': b'public-adapter', 'lib/arm64-v8a/libapp.so': b'synthetic-aot',
                       'lib/arm64-v8a/libflutter.so': synthetic_elf()}
            def write(values):
                with zipfile.ZipFile(apk, 'w') as archive:
                    for name, data in values.items(): archive.writestr(name, data)
            write(entries)
            expected = {'assets/public.js': b'public-adapter'}
            self.assertEqual(verify.check_zip(apk, expected, 'release', folder, [folder]), ['arm64-v8a'])
            for change in [{'assets/synthetic-media/fixture.json': b'{}'},
                           {'assets/public.js': b'changed'},
                           {'lib/arm64-v8a/libflutter.so': synthetic_elf(b'profile-engine')},
                           {'assets/flutter_assets/kernel_blob.bin': b'debug-kernel'},
                           {'assets/classroom-library-v1.json': b'synthetic private cache'}]:
                with self.subTest(change=list(change)):
                    write({**entries, **change})
                    with self.assertRaises(ValueError):
                        verify.check_zip(apk, expected, 'release', folder, [folder])

    def test_corrupt_zip_is_not_a_valid_artifact(self):
        with synthetic_directory() as folder:
            path = Path(folder) / 'synthetic.apk'
            path.write_bytes(b'synthetic broken zip')
            with self.assertRaises(zipfile.BadZipFile):
                verify.check_zip(path, {}, 'release', Path(folder), [Path(folder)])

    def test_engine_fingerprint_allows_symbol_stripping_but_rejects_code_change(self):
        original = synthetic_elf()
        stripped = bytearray(original)
        struct.pack_into('<Q', stripped, 40, 128)  # rewritten section table
        self.assertEqual(verify.executable_fingerprint(original), verify.executable_fingerprint(stripped))
        self.assertNotEqual(verify.executable_fingerprint(original), verify.executable_fingerprint(synthetic_elf(b'profile-engine')))
