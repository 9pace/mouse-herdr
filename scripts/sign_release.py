#!/usr/bin/env python3
"""Sign and notarize a release using credentials supplied only to this process."""

import base64
import binascii
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys
import tempfile
from urllib.request import urlopen

from bundle_signing import sparkle_targets


SECRET_NAMES = (
    "MACOS_CERTIFICATE_P12",
    "MACOS_CERTIFICATE_PASSWORD",
    "APPLE_ID",
    "APPLE_TEAM_ID",
    "APPLE_APP_SPECIFIC_PASSWORD",
)
INTERMEDIATE_URL = "https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"


class ReleaseSigner:
    def __init__(self, credentials):
        missing = [name for name in SECRET_NAMES if not credentials.get(name)]
        if missing:
            raise ValueError("Missing release secrets: " + ", ".join(missing))
        try:
            self.certificate = base64.b64decode(credentials[SECRET_NAMES[0]], validate=True)
        except (ValueError, binascii.Error):
            raise ValueError("MACOS_CERTIFICATE_P12 must be base64-encoded PKCS#12.") from None
        if not self.certificate:
            raise ValueError("MACOS_CERTIFICATE_P12 is empty.")
        self.credentials = credentials
        self.keychain_password = secrets.token_urlsafe(32)
        self.redactions = [*credentials.values(), self.keychain_password]

    def run(self, *args):
        # Only the command that needs a credential receives it. In particular,
        # codesign and packaging tools do not inherit the GitHub secrets.
        environment = {key: value for key, value in os.environ.items()
                       if key not in SECRET_NAMES}
        result = subprocess.run(args, capture_output=True, text=True, env=environment)
        if result.returncode:
            detail = result.stderr.strip()
            for value in sorted(self.redactions, key=len, reverse=True):
                detail = detail.replace(value, "<redacted>")
            raise RuntimeError(f"{Path(args[0]).name} failed ({result.returncode}): {detail}")
        return result.stdout

    def sign(self, app):
        app = Path(app).resolve(strict=True)
        if not (app / "Contents/MacOS/MouseHerdr").is_file():
            raise ValueError("Expected a built MouseHerdr.app bundle.")
        nested_code = sparkle_targets(app)
        original_keychains = shlex.split(self.run("security", "list-keychains", "-d", "user"))
        with tempfile.TemporaryDirectory(prefix="mouseherdr-release-",
                                         dir=os.environ.get("RUNNER_TEMP")) as directory:
            work = Path(directory)
            keychain = str(work / "release.keychain-db")
            p12 = work / "certificate.p12"
            p12.write_bytes(self.certificate)
            p12.chmod(0o600)
            # Xcode versions differ in which intermediate certificates they include.
            intermediate = work / "DeveloperIDG2CA.cer"
            with urlopen(INTERMEDIATE_URL, timeout=30) as response:
                intermediate.write_bytes(response.read())
            created = False
            try:
                self.run("security", "create-keychain", "-p", self.keychain_password, keychain)
                created = True
                self.run("security", "set-keychain-settings", "-lut", "21600", keychain)
                self.run("security", "unlock-keychain", "-p", self.keychain_password, keychain)
                self.run("security", "list-keychains", "-d", "user", "-s",
                         keychain, *original_keychains)
                self.run("security", "import", str(p12), "-k", keychain,
                         "-P", self.credentials["MACOS_CERTIFICATE_PASSWORD"],
                         "-T", "/usr/bin/codesign")
                p12.unlink()
                self.run("security", "import", str(intermediate), "-k", keychain)
                self.run("security", "set-key-partition-list", "-S",
                         "apple-tool:,apple:,codesign:", "-s",
                         "-k", self.keychain_password, keychain)
                identities = self.run("security", "find-identity", "-v", "-p",
                                      "codesigning", keychain)
                matches = re.findall(
                    r'\b([A-Fa-f0-9]{40}) "Developer ID Application: ([^"]+)"', identities)
                if len(matches) != 1:
                    raise RuntimeError("Expected exactly one valid Developer ID Application identity.")
                fingerprint, identity_name = matches[0]
                self.redactions.extend([fingerprint, identity_name])
                if not identity_name.endswith(f" ({self.credentials['APPLE_TEAM_ID']})"):
                    raise RuntimeError("The signing certificate does not match APPLE_TEAM_ID.")
                for target in nested_code:
                    self.run("codesign", "--force", "--options", "runtime", "--timestamp",
                             "--preserve-metadata=identifier,entitlements",
                             "--keychain", keychain, "--sign", fingerprint, str(target))
                self.run("codesign", "--force", "--options", "runtime", "--timestamp",
                         "--keychain", keychain, "--sign", fingerprint, str(app))
                self.run("codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app))

                profile = "MouseHerdr-release"
                self.run("xcrun", "notarytool", "store-credentials", profile,
                         "--apple-id", self.credentials["APPLE_ID"],
                         "--team-id", self.credentials["APPLE_TEAM_ID"],
                         "--password", self.credentials["APPLE_APP_SPECIFIC_PASSWORD"],
                         "--keychain", keychain)
                archive = work / "MouseHerdr.zip"
                self.run("ditto", "-c", "-k", "--keepParent", str(app), str(archive))
                response = json.loads(self.run(
                    "xcrun", "notarytool", "submit", str(archive),
                    "--keychain-profile", profile, "--keychain", keychain,
                    "--wait", "--timeout", "20m", "--output-format", "json"))
                if response.get("status") != "Accepted":
                    raise RuntimeError(
                        f"Apple did not accept notarization: {response.get('status', 'unknown')}; "
                        f"submission {response.get('id', 'unknown')}. No release will be published.")
                print(f"Apple accepted notarization: {response['id']}")
                self.run("xcrun", "stapler", "staple", str(app))
                self.run("xcrun", "stapler", "validate", str(app))
                self.run("spctl", "--assess", "--type", "execute", str(app))
                print("Verified Developer ID signature, notarization ticket, and Gatekeeper acceptance.")
            finally:
                if created:
                    # Attempt both operations even if one fails. These are isolated
                    # release runners; restore the search list before deleting the keychain.
                    try:
                        self.run("security", "list-keychains", "-d", "user", "-s",
                                 *original_keychains)
                    finally:
                        self.run("security", "delete-keychain", keychain)


def main():
    if len(sys.argv) > 2:
        raise ValueError("Usage: sign_release.py [path/to/MouseHerdr.app]")
    credentials = {name: os.environ.pop(name, "") for name in SECRET_NAMES}
    ReleaseSigner(credentials).sign(sys.argv[1] if len(sys.argv) == 2 else "dist/MouseHerdr.app")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError) as error:
        sys.exit(str(error))
