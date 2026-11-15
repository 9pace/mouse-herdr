#!/usr/bin/env python3
"""Exercise feed metadata, signing failures and real Ed25519 verification."""

import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from update_feed import FEED_URL, SIGN_TOOL, SPARKLE, make_feed, prepare_notes, publish_feed, sign


def metadata(public_key="test-public-key"):
    return {
        "CFBundleIdentifier": "dev.mouseherdr.app",
        "CFBundleShortVersionString": "1.0.50",
        "CFBundleVersion": "50",
        "LSMinimumSystemVersion": "13.0",
        "SUPublicEDKey": public_key,
        "SUFeedURL": FEED_URL,
        "MouseHerdrReleaseBuild": True,
    }


class FeedTests(unittest.TestCase):
    def test_feed_uses_exact_release_asset_build_number_and_escaped_notes(self):
        notes = '## What’s New\n- Fix <drag> & "drop"\n- [Details](https://example.com)'
        root = ET.fromstring(make_feed(metadata(), notes, 1234, base64.b64encode(bytes(64)).decode()))
        item = root.find("channel/item")
        self.assertEqual(item.findtext(f"{{{SPARKLE}}}version"), "50")
        self.assertEqual(item.findtext(f"{{{SPARKLE}}}shortVersionString"), "1.0.50")
        self.assertEqual(item.findtext(f"{{{SPARKLE}}}minimumSystemVersion"), "13.0")
        self.assertEqual(item.findtext("description"), notes)
        self.assertEqual(item.find("description").get(f"{{{SPARKLE}}}format"), "markdown")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"),
                         "https://github.com/royosherove/mouse-herdr/releases/download/v1.0.50/MouseHerdr.zip")
        self.assertEqual(enclosure.get("length"), "1234")

    def test_wrong_identity_feed_or_invalid_release_cannot_be_published(self):
        for field, value in [
            ("CFBundleIdentifier", "test.other-app"),
            ("MouseHerdrReleaseBuild", False),
            ("SUFeedURL", "https://example.com/feed"),
            ("CFBundleVersion", "0"),
            ("CFBundleVersion", "dev"),
            ("CFBundleShortVersionString", "1.0"),
            ("CFBundleShortVersionString", "1.0.50/other"),
        ]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                make_feed({**metadata(), field: value}, "", 123, base64.b64encode(bytes(64)).decode())

    def test_notes_are_generated_for_exact_commit_and_previous_release(self):
        with tempfile.TemporaryDirectory() as work, patch("update_feed.subprocess.run") as run:
            run.return_value.stdout = json.dumps({"body": "## What's Changed\n- Improved scrolling"})
            output = Path(work) / "ReleaseNotes.md"
            prepare_notes("1.0.50", "a" * 40, "v1.0.48", output)
            self.assertEqual(json.loads(run.call_args.kwargs["input"]), {
                "tag_name": "v1.0.50", "target_commitish": "a" * 40, "previous_tag_name": "v1.0.48",
            })
            self.assertEqual(output.read_text(), "## What's Changed\n- Improved scrolling\n")

    def test_private_key_only_reaches_stdin_and_tool_errors_cannot_leak_it(self):
        with patch.dict(os.environ, {"SPARKLE_PRIVATE_KEY": "private-test-key"}), patch(
            "update_feed.subprocess.run",
            return_value=subprocess.CompletedProcess([], 1, "", "error with private-test-key"),
        ) as run:
            with self.assertRaises(RuntimeError) as error:
                sign(SIGN_TOOL, "private-test-key", "archive.zip")
            self.assertNotIn("private-test-key", str(error.exception))
            self.assertNotIn("private-test-key", run.call_args.args[0])
            self.assertNotIn("SPARKLE_PRIVATE_KEY", run.call_args.kwargs["env"])
            self.assertEqual(run.call_args.kwargs["input"], "private-test-key")


@unittest.skipUnless(SIGN_TOOL.is_file(), "Run swift package resolve to test real Sparkle signing")
class SignatureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Ephemeral test credentials only; never access the user's Keychain.
        result = subprocess.run(["swift", "-e", """
            import CryptoKit
            import Foundation
            let key = Curve25519.Signing.PrivateKey()
            print(key.rawRepresentation.base64EncodedString())
            print(key.publicKey.rawRepresentation.base64EncodedString())
        """], capture_output=True, text=True, check=True)
        cls.private_key, cls.public_key = result.stdout.strip().splitlines()

    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.app = Path(self.work.name) / "MouseHerdr.app"
        (self.app / "Contents/Resources").mkdir(parents=True)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata(self.public_key)))
        (self.app / "Contents/Resources/ReleaseNotes.md").write_text("## Changes\n- Smoother scrolling")
        self.archive = Path(self.work.name) / "MouseHerdr.zip"
        # Signing operates on bytes; this fixture never runs the installer.
        self.archive.write_bytes(b"test archive contents")
        self.feed = Path(self.work.name) / "appcast.xml"

    def test_real_archive_and_feed_signatures_verify_and_tampering_is_rejected(self):
        publish_feed(self.app, self.archive, self.feed, self.private_key)
        root = ET.fromstring(self.feed.read_bytes())
        signature = root.find("channel/item/enclosure").get(f"{{{SPARKLE}}}edSignature")
        sign(SIGN_TOOL, self.private_key, "--verify", str(self.feed))
        self.archive.write_bytes(b"tampered archive")
        result = subprocess.run(["swift", "scripts/verify_update.swift", self.public_key,
                                 str(self.archive), signature], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.feed.write_text(self.feed.read_text().replace("Smoother scrolling", "Injected notes"))
        with self.assertRaises(RuntimeError):
            sign(SIGN_TOOL, self.private_key, "--verify", str(self.feed))

    def test_wrong_ci_key_stops_before_writing_feed(self):
        info = metadata(base64.b64encode(bytes(32)).decode())
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaises(subprocess.CalledProcessError):
            publish_feed(self.app, self.archive, self.feed, self.private_key)
        self.assertFalse(self.feed.exists())

    def test_missing_secret_stops_before_writing_feed(self):
        with self.assertRaisesRegex(ValueError, "SPARKLE_PRIVATE_KEY"):
            publish_feed(self.app, self.archive, self.feed, "")
        self.assertFalse(self.feed.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
