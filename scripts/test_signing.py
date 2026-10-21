"""Offline regression checks for the signing helper; no Apple API calls or signing."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch
from datetime import datetime, timedelta

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('signing', root / 'scripts/apply_profile.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)

class SigningTests(unittest.TestCase):
    def test_valid_nested_bundle_resource(self):
        data = json.dumps({'data': [{'id': 'correct-resource', 'attributes': {'identifier': signing.BUNDLE}}]})
        output = io.StringIO()
        with patch.object(signing, 'Path') as path, contextlib.redirect_stdout(output):
            path.return_value.exists.return_value = True
            path.return_value.read_text.return_value = data
            signing.print_bundle_resource_id('fixture.json')
        self.assertEqual(output.getvalue().strip(), 'correct-resource')

    def test_missing_bundle_fails_instead_of_using_old_account_id(self):
        data = json.dumps({'data': [{'id': 'unrelated', 'identifier': 'other.app'}]})
        with patch.object(signing, 'Path') as path:
            path.return_value.exists.return_value = True
            path.return_value.read_text.return_value = data
            with self.assertRaises(SystemExit):
                signing.print_bundle_resource_id('fixture.json')

    def test_entitlements_reject_ndef(self):
        self.assertTrue(signing.tag_only({signing.NFC_KEY: ['TAG']}))
        self.assertFalse(signing.tag_only({signing.NFC_KEY: ['TAG', 'NDEF']}))
        self.assertFalse(signing.tag_only({}))

    def test_entitlements_extract_from_codesign_diagnostics(self):
        data = plistlib.dumps({signing.NFC_KEY: ['TAG']})
        self.assertTrue(signing.blob_claims_tag(b'Executable=/tmp/Test.app\n' + data + b'\nwarning: diagnostic'))
        self.assertFalse(signing.blob_claims_tag(b'not a plist TAG'))

    def test_expired_profile_is_not_usable(self):
        self.assertFalse(signing.is_app_store({'Platform': ['iOS'], 'ExpirationDate': datetime.now() - timedelta(days=1)}))

    def test_development_and_enterprise_profiles_are_not_app_store(self):
        self.assertFalse(signing.is_app_store({'ProvisionedDevices': ['device'], 'Platform': ['iOS']}))
        self.assertFalse(signing.is_app_store({'ProvisionsAllDevices': True, 'Platform': ['iOS']}))
        self.assertFalse(signing.is_app_store({'Entitlements': {'get-task-allow': True}, 'Platform': ['iOS']}))

    def test_no_tag_profile_fails_before_signing(self):
        profile = {'Name': 'no tag', 'Platform': ['iOS'], 'Entitlements': {}, 'ExpirationDate': datetime.now() + timedelta(days=30)}
        with patch.object(signing, 'project_root', return_value=root), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit):
                signing.choose_profile([('/unused/profile', profile)])

    def test_build_settings_preserve_other_target(self):
        source = '''buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = eu.refurbx.diagnostics;
    CODE_SIGN_STYLE = Automatic;
};
buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = other.application;
    CUSTOM_SETTING = keep;
};'''
        result = signing.patch_build_settings(source, 'test-uuid', 'Test Profile', 'test-identity')
        self.assertIn('PROVISIONING_PROFILE_SPECIFIER = "test-uuid";', result)
        self.assertIn('CODE_SIGN_ENTITLEMENTS = RefurbX/RefurbX.entitlements;', result)
        self.assertIn('CUSTOM_SETTING = keep;', result)
        self.assertEqual(result.count('PROVISIONING_PROFILE_SPECIFIER'), 1)

if __name__ == '__main__':
    unittest.main(verbosity=2)
