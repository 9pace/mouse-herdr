#!/usr/bin/env python3
"""Check build failure handling and, optionally, the packaged app's Herdr and mouse diagnostics."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
BINARY = os.environ.get("MOUSEHERDR_TEST_BINARY")


@unittest.skipUnless(sys.platform == "darwin", "MouseHerdr builds on macOS")
class BuildScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="mouse herdr build ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copy2(ROOT / "build.sh", self.root / "build.sh")
        tools = self.root / "tools"
        tools.mkdir()
        swift = tools / "swift"
        swift.write_text(
            '#!/bin/sh\n'
            'touch "$COMPILER_MARKER"\n'
            'echo "intentional compiler failure" >&2\n'
            'exit 23\n'
        )
        swift.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                        BUNDLE_ID="dev.mouseherdr.test", SIGNING="adhoc",
                        COMPILER_MARKER=str(self.root / "compiler-called"))

    def run_build(self, *args):
        return subprocess.run(
            ["/bin/bash", str(self.root / "build.sh"), *args],
            cwd=self.root.parent, env=self.env, capture_output=True, text=True, timeout=10,
        )

    def test_failed_compilation_cannot_package_an_old_binary(self):
        stale = self.root / ".build/release/MouseHerdr"
        stale.parent.mkdir(parents=True)
        stale.write_text('#!/bin/sh\ntouch "$STALE_MARKER"\nexit 0\n')
        stale.chmod(0o755)
        self.env["STALE_MARKER"] = str(self.root / "stale-used")
        previous = self.root / "dist/MouseHerdr.app/previous-build"
        previous.parent.mkdir(parents=True)
        previous.write_text("previous successful build")

        result = self.run_build()

        self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
        self.assertIn("intentional compiler failure", result.stderr)
        self.assertFalse((self.root / "stale-used").exists())
        self.assertEqual(previous.read_text(), "previous successful build")

    def test_invalid_bundle_id_is_rejected_before_building(self):
        self.env["BUNDLE_ID"] = "invalid<&identifier"
        result = self.run_build()
        self.assertEqual(result.returncode, 2)
        self.assertIn("BUNDLE_ID", result.stderr)
        self.assertFalse((self.root / "compiler-called").exists())

    def test_unknown_argument_is_rejected_before_building(self):
        result = self.run_build("instal")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Usage:", result.stderr)
        self.assertFalse((self.root / "compiler-called").exists())

    def test_help_does_not_build_or_change_keychains(self):
        result = self.run_build("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout)
        self.assertFalse((self.root / "compiler-called").exists())
        self.assertFalse((self.root / "signing").exists())


@unittest.skipUnless(BINARY, "Set MOUSEHERDR_TEST_BINARY to test a packaged app")
class HerdrSetupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="mouse herdr hc ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.hc = self.root / "hc"
        self.env = dict(os.environ, MOUSEHERDR_HC=str(self.hc),
                        MOUSEHERDR_HERDR_APP=str(self.root / "missing-herdr-app"))

    def status(self, script=None):
        if script is not None:
            self.hc.write_text("#!/bin/sh\n" + script + "\n")
            self.hc.chmod(0o755)
        result = subprocess.run(
            [str(Path(BINARY).resolve()), "--herdr-status"],
            env=self.env, capture_output=True, text=True, timeout=12,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Herdr app: not installed", result.stdout)
        return result.stdout

    def test_missing_optional_dependency(self):
        self.assertIn("herdr-core: not installed", self.status())

    def test_failed_and_invalid_listing(self):
        for script in ["exit 1", "printf 'invalid json'"]:
            with self.subTest(script=script):
                self.assertIn("installed, but not running", self.status(script))

    def test_empty_and_populated_listing(self):
        self.assertIn("running, no agents", self.status("""printf '%s' '{"terminals":[]}'"""))
        self.assertIn("running, 1 agent", self.status(
            """printf '%s' '{"terminals":[{"address":"t1","agent":"claude-code","status":"working","where":"demo / 1"}]}'"""
        ))

    def test_unresponsive_service_has_a_bounded_wait(self):
        started = time.monotonic()
        self.assertIn("installed, but not running", self.status("exec /bin/sleep 30"))
        self.assertLess(time.monotonic() - started, 10)


@unittest.skipUnless(BINARY, "Set MOUSEHERDR_TEST_BINARY to test a packaged app")
class MouseDetectionTests(unittest.TestCase):
    """How the packaged app recognises mice. None of this needs a mouse, a permission or Herdr."""

    def run_app(self, *args):
        return subprocess.run(
            [str(Path(BINARY).resolve()), *args], capture_output=True, text=True, timeout=20,
        )

    def identify(self, *args):
        result = self.run_app("--identify", *args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def test_mice_of_several_makers_are_recognised(self):
        cases = [
            ("046d:b042", "MX Master 4", "mxMaster4: Logitech MX Master 4 (recognised, tested)"),
            ("046d:b034", "MX Master 3S", "mxMaster3S: Logitech MX Master 3S (recognised)"),
            ("045e:00cb", "Microsoft USB Optical Mouse", "msBasicOptical: Microsoft Basic Optical Mouse (recognised)"),
            ("045e:0823", "Microsoft Classic IntelliMouse", "msIntelliMouse: Microsoft Classic / Pro IntelliMouse (recognised)"),
            ("004c:0269", "Magic Mouse", "magicMouse: Apple Magic Mouse (recognised)"),
            ("1532:0084", "Razer DeathAdder V2", "razerDeathAdder: Razer DeathAdder (recognised)"),
            ("1038:1824", "SteelSeries Rival 3", "steelSeriesRival: SteelSeries Rival (recognised)"),
            ("1b1c:1b5a", "CORSAIR M65 RGB ELITE Gaming Mouse", "corsairM65: Corsair M65 (recognised)"),
            ("047d:1020", "Kensington Expert Mouse", "kensingtonExpert: Kensington Expert Mouse (recognised)"),
        ]
        for ids, name, expected in cases:
            with self.subTest(mouse=name):
                self.assertEqual(self.identify(ids, name), expected)

    def test_a_mouse_is_recognised_by_name_when_its_id_is_not_listed(self):
        self.assertEqual(self.identify("045e:0fff", "Surface Arc Mouse"), "msArc: Microsoft Arc Mouse (recognised)")
        self.assertEqual(self.identify("0000:0000", "Someone's Magic Mouse"), "magicMouse: Apple Magic Mouse (recognised)")

    def test_a_receiver_is_not_taken_for_a_mouse_model(self):
        self.assertEqual(
            self.identify("046d:c52b", "USB Receiver"),
            "logitechReceiver: Logitech USB receiver (receiver, mouse model unknown)",
        )

    def test_an_unknown_mouse_gets_a_layout_for_its_buttons(self):
        for buttons, expected in [("2", "generic2"), ("3", "generic3"), ("5", "generic"), ("16", "generic")]:
            with self.subTest(buttons=buttons):
                self.assertEqual(
                    self.identify("1234:5678", "Wireless Mouse", "--buttons", buttons),
                    f"{expected}: Wireless Mouse (not in the list)",
                )
        # A mouse that doesn't say how many buttons it has is assumed to have side buttons.
        self.assertEqual(self.identify("1234:5678", "Wireless Mouse"), "generic: Wireless Mouse (not in the list)")

    def test_a_trackpad_is_not_a_mouse(self):
        self.assertEqual(self.identify("05ac:0265", "Magic Trackpad"), "ignored: Magic Trackpad is not a mouse")

    def test_ids_that_are_not_hexadecimal_are_rejected(self):
        for args in [("--identify",), ("--identify", "microsoft"), ("--identify", "045e"), ("--identify", "045e:zz")]:
            with self.subTest(args=args):
                result = self.run_app(*args)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("--identify <vendor>:<product>", result.stdout)

    def test_the_list_covers_the_well_known_makers(self):
        result = self.run_app("--list-mice")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rows = [line.split("\t") for line in result.stdout.splitlines()]
        self.assertTrue(all(len(row) == 3 for row in rows), result.stdout)
        ids = [row[0] for row in rows]
        self.assertEqual(len(ids), len(set(ids)), "every profile has its own id")
        self.assertGreaterEqual(len(rows), 50)
        brands = {row[1] for row in rows}
        for brand in ["Apple", "Logitech", "Microsoft", "Razer", "SteelSeries", "Corsair", "Kensington"]:
            self.assertIn(brand, brands)
        for profile in ["mxMaster4", "generic", "generic3", "generic2"]:
            self.assertIn(profile, ids)

    def test_looking_for_connected_mice_is_quick_and_asks_for_nothing(self):
        started = time.monotonic()
        result = self.run_app("--detect-mice")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertLess(time.monotonic() - started, 10)
        lines = result.stdout.splitlines()
        # A build server has no mouse; a desk has one or more. Both are fine.
        if "No mouse found." in lines:
            self.assertFalse(any(line.startswith("* ") for line in lines), result.stdout)
        else:
            self.assertIn("Mice connected:", lines)
            self.assertEqual(sum(line.startswith("* ") for line in lines), 1, "one mouse is followed")
            self.assertTrue(any(line.startswith("MouseHerdr would follow: ") for line in lines), result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
