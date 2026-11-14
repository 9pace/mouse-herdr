#!/usr/bin/env python3
"""Check that release failures cannot publish an unsigned or unnotarized app."""

import base64
from io import BytesIO
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from sign_release import ReleaseSigner, SECRET_NAMES


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.app = Path(self.tmp.name) / "MouseHerdr.app"
        binary = self.app / "Contents/MacOS/MouseHerdr"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"test executable")
        self.credentials = dict.fromkeys(SECRET_NAMES, "private-test-value")
        self.credentials["MACOS_CERTIFICATE_P12"] = base64.b64encode(b"test p12").decode()
        self.credentials["APPLE_TEAM_ID"] = "TEAM"
        self.commands = []
        self.status = "Accepted"
        self.failure = None
        self.identities = '1) ' + "A" * 40 + ' "Developer ID Application: Test (TEAM)"'

    def fake_run(self, *args):
        self.commands.append(args)
        if self.failure and args[:len(self.failure)] == self.failure:
            raise RuntimeError("simulated failure")
        if args == ("security", "list-keychains", "-d", "user"):
            return '"/tmp/keychain with spaces/login.keychain-db"\n'
        if args[:2] == ("security", "find-identity"):
            return self.identities
        if args[:3] == ("xcrun", "notarytool", "submit"):
            return json.dumps({"status": self.status, "id": "test-submission"})
        return ""

    def sign(self):
        signer = ReleaseSigner(self.credentials)
        with patch.object(signer, "run", side_effect=self.fake_run), patch(
            "sign_release.urlopen", return_value=BytesIO(b"test intermediate"),
        ):
            signer.sign(self.app)

    def called(self, *prefix):
        return any(command[:len(prefix)] == prefix for command in self.commands)

    def assert_cleanup(self):
        self.assertTrue(self.called("security", "delete-keychain"))
        self.assertIn(("security", "list-keychains", "-d", "user", "-s",
                       "/tmp/keychain with spaces/login.keychain-db"), self.commands)
        created = next(c for c in self.commands if c[:2] == ("security", "create-keychain"))
        self.assertFalse(Path(created[-1]).parent.exists())

    def test_missing_or_invalid_secrets_stop_before_using_keychain(self):
        for changes in [
            {"APPLE_APP_SPECIFIC_PASSWORD": ""},
            {"MACOS_CERTIFICATE_P12": "not base64"},
        ]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                ReleaseSigner({**self.credentials, **changes})

    def test_accepted_submission_is_stapled_and_assessed_then_credentials_removed(self):
        self.sign()
        self.assertTrue(self.called("codesign", "--force", "--options", "runtime", "--timestamp"))
        self.assertTrue(self.called("xcrun", "stapler", "staple"))
        self.assertTrue(self.called("xcrun", "stapler", "validate"))
        self.assertTrue(self.called("spctl", "--assess"))
        self.assert_cleanup()

    def test_rejected_or_incomplete_notarization_never_reaches_stapling(self):
        for status in ["Invalid", "In Progress", None]:
            with self.subTest(status=status):
                self.commands = []
                self.status = status
                with self.assertRaisesRegex(RuntimeError, "did not accept"):
                    self.sign()
                self.assertFalse(self.called("xcrun", "stapler"))
                self.assert_cleanup()

    def test_signing_failure_cannot_submit_to_apple_and_removes_credentials(self):
        self.failure = ("codesign", "--force")
        with self.assertRaises(RuntimeError):
            self.sign()
        self.assertFalse(self.called("xcrun", "notarytool"))
        self.assert_cleanup()

    def test_notary_timeout_and_stapling_failure_stop_the_release_and_clean_up(self):
        for failure in [("xcrun", "notarytool", "submit"), ("xcrun", "stapler", "staple")]:
            with self.subTest(failure=failure):
                self.commands = []
                self.failure = failure
                with self.assertRaises(RuntimeError):
                    self.sign()
                self.assertFalse(self.called("spctl", "--assess"))
                self.assert_cleanup()

    def test_missing_or_ambiguous_identity_is_rejected(self):
        for identities in ["0 valid identities found", self.identities + "\n" + self.identities]:
            with self.subTest(identities=identities):
                self.commands = []
                self.identities = identities
                with self.assertRaisesRegex(RuntimeError, "exactly one"):
                    self.sign()
                self.assertFalse(self.called("codesign"))
                self.assert_cleanup()

    def test_import_failure_also_deletes_the_temporary_keychain(self):
        self.failure = ("security", "import")
        with self.assertRaises(RuntimeError):
            self.sign()
        self.assert_cleanup()

    def test_certificate_from_another_team_is_rejected_before_signing(self):
        self.credentials["APPLE_TEAM_ID"] = "OTHERTEAM"
        with self.assertRaisesRegex(RuntimeError, "does not match APPLE_TEAM_ID"):
            self.sign()
        self.assertFalse(self.called("codesign"))
        self.assertFalse(self.called("xcrun", "notarytool"))
        self.assert_cleanup()

    def test_tool_errors_redact_secrets_and_children_do_not_inherit_them(self):
        signer = ReleaseSigner(self.credentials)
        failure = subprocess.CompletedProcess(
            ["security"], 1, "", "failure: private-test-value " + signer.keychain_password)
        with patch.dict("os.environ", self.credentials), patch(
            "sign_release.subprocess.run", return_value=failure,
        ) as command:
            with self.assertRaises(RuntimeError) as caught:
                signer.run("security", "import")
        self.assertNotIn("private-test-value", str(caught.exception))
        self.assertNotIn(signer.keychain_password, str(caught.exception))
        for name in SECRET_NAMES:
            self.assertNotIn(name, command.call_args.kwargs["env"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
