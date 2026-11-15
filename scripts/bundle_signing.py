"""The nested Sparkle code to sign, from the inside out."""

from pathlib import Path
import subprocess
import sys


def sparkle_targets(app):
    framework = Path(app) / "Contents/Frameworks/Sparkle.framework"
    if not framework.is_dir():
        raise ValueError("Sparkle.framework is missing from the app.")
    version = framework / "Versions/B"
    targets = [
        version / "XPCServices/Downloader.xpc",
        version / "XPCServices/Installer.xpc",
        version / "Autoupdate",
        version / "Updater.app",
        framework,
    ]
    if any(not target.exists() for target in targets):
        raise ValueError("The embedded Sparkle framework is incomplete.")
    return targets


if __name__ == "__main__":
    # Used by build.sh with either "-" or its existing local signing identity.
    app, *signing_args = sys.argv[1:]
    for target in sparkle_targets(app):
        subprocess.run(["codesign", "--force", "--preserve-metadata=identifier,entitlements",
                        *signing_args, str(target)], check=True)
