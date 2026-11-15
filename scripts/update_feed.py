#!/usr/bin/env python3
"""Prepare offline release notes and a signed Sparkle feed for a GitHub release."""

import base64
from datetime import datetime, timezone
from email.utils import format_datetime
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
REPOSITORY = "royosherove/mouse-herdr"
FEED_URL = f"https://github.com/{REPOSITORY}/releases/latest/download/appcast.xml"
SIGN_TOOL = Path(".build/artifacts/sparkle/Sparkle/bin/sign_update")


def prepare_notes(version, sha, previous_tag, destination):
    payload = {"tag_name": f"v{version}", "target_commitish": sha}
    if previous_tag:
        payload["previous_tag_name"] = previous_tag
    result = subprocess.run(
        ["gh", "api", "--method", "POST", f"repos/{REPOSITORY}/releases/generate-notes",
         "--input", "-"], input=json.dumps(payload), capture_output=True, text=True, check=True)
    notes = json.loads(result.stdout)["body"].strip()
    if not notes:
        notes = "Maintenance improvements in this release."
    Path(destination).parent.mkdir(parents=True, exist_ok=True)
    Path(destination).write_text(notes + "\n", encoding="utf-8")


def make_feed(info, notes, archive_size, signature, now=None):
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("The update must have a release version and a positive build number.")
    if info["CFBundleIdentifier"] != "dev.mouseherdr.app" or info["SUFeedURL"] != FEED_URL:
        raise ValueError("Refusing to publish an update for a different app or feed.")
    if info.get("MouseHerdrReleaseBuild") is not True:
        raise ValueError("Refusing to publish a source build as an automatic update.")
    if archive_size <= 0 or len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("The archive size or EdDSA signature is invalid.")
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "MouseHerdr"
    ET.SubElement(channel, "link").text = f"https://github.com/{REPOSITORY}/releases"
    ET.SubElement(channel, "language").text = "en"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"MouseHerdr {version}"
    ET.SubElement(item, "pubDate").text = format_datetime(now or datetime.now(timezone.utc))
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
    ET.SubElement(item, "description", {f"{{{SPARKLE}}}format": "markdown"}).text = notes
    ET.SubElement(item, f"{{{SPARKLE}}}fullReleaseNotesLink").text = f"https://github.com/{REPOSITORY}/releases"
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/{REPOSITORY}/releases/download/v{version}/MouseHerdr.zip",
        "length": str(archive_size), "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": signature,
    })
    ET.indent(root)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def sign(tool, private_key, *args):
    # The secret goes only to this child's stdin. Never put it in argv or exception output.
    environment = {k: v for k, v in os.environ.items() if k != "SPARKLE_PRIVATE_KEY"}
    result = subprocess.run([str(tool), "--ed-key-file", "-", *args],
                            input=private_key, text=True, capture_output=True, env=environment)
    if result.returncode:
        raise RuntimeError("Sparkle signing or verification failed; no update will be published.")
    return result.stdout.strip()


def publish_feed(app, archive, output, private_key, tool=SIGN_TOOL):
    if not private_key:
        raise ValueError("Missing release secret: SPARKLE_PRIVATE_KEY.")
    app, archive, output = Path(app), Path(archive), Path(output)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    notes = (app / "Contents/Resources/ReleaseNotes.md").read_text(encoding="utf-8")
    signature = sign(tool, private_key, "-p", str(archive))
    # Catch a mismatched/rotated CI secret before publishing an update nobody can install.
    subprocess.run(["swift", "scripts/verify_update.swift", info["SUPublicEDKey"],
                    str(archive), signature], check=True)
    output.write_bytes(make_feed(info, notes, archive.stat().st_size, signature))
    sign(tool, private_key, str(output))
    sign(tool, private_key, "--verify", str(output))


def main():
    mode = sys.argv[1] if len(sys.argv) == 2 else ""
    if mode == "notes":
        prepare_notes(os.environ["VERSION"], os.environ["RELEASE_SHA"],
                      os.environ.get("PREVIOUS_TAG", ""), "dist/ReleaseNotes.md")
    elif mode == "sign":
        private_key = os.environ.pop("SPARKLE_PRIVATE_KEY", "")
        publish_feed("dist/MouseHerdr.app", "dist/MouseHerdr.zip", "dist/appcast.xml", private_key)
    else:
        raise ValueError("Usage: update_feed.py notes|sign")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
