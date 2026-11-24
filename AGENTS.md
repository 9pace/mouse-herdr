# Repository instructions

## Commit attribution

Credit human contributors only. Never add Claude or another AI assistant as a
commit co-author. Do not add `Co-Authored-By` trailers naming Claude or using
`noreply@anthropic.com`.

Check the commit message before committing. Preserve the human author's identity
and any genuine human co-author credits.

## Branch names

Use purpose-based names such as `feature/<topic>`, `bug/<topic>`, `docs/<topic>`,
or `chore/<topic>`. Never use `codex/` or another agent-name prefix.

## Build and test

From the checkout or worktree you are working in:

```bash
swift test
python3 scripts/test_release.py
python3 scripts/test_sign_release.py
SIGNING=adhoc ./build.sh
MOUSEHERDR_TEST_BINARY=dist/MouseHerdr.app/Contents/MacOS/MouseHerdr python3 scripts/test_setup.py
```

`SIGNING=adhoc` builds `dist/MouseHerdr.app` without creating a keychain or changing the
keychain search list. Use it for every build that is only tested. `./build.sh` never
installs. `./build.sh install` replaces the copy in `/Applications` and restarts it, so
run it only when the owner asks.

A copy of MouseHerdr is usually running on the owner's Mac with the mouse's buttons
captured. A second copy would fight it for the mouse, so:

- Run a built binary only with a developer flag that does one job and exits: `--snapshot`,
  `--snapshot-ring`, `--snapshot-mice`, `--detect-mice`, `--identify`, `--list-mice` or
  `--herdr-status`. Never start a built copy with no flag while another copy is running.
- `--preview-ring` is the one flag that puts something on the owner's screen: the wheel,
  with sample agents, at the pointer, until it is closed. It takes no button and sends
  nothing, but run it only when the owner asks to see the wheel.
- Give such a run an empty home folder, so that it reads default settings and leaves the
  real settings and log alone:
  `CFFIXED_USER_HOME=/tmp/mouseherdr-home dist/MouseHerdr.app/Contents/MacOS/MouseHerdr --snapshot /tmp/window.png`

## Sign a build with the owner's identity

macOS ties Accessibility and Input Monitoring to the app's identifier and signing
certificate. An ad-hoc build has neither permission, so it cannot remap anything. A build
that is to run for real has to be signed the way the installed copy is.

The identifier and the certificate belong to the owner's Mac and are not in the repository:
the identifier is in the main checkout's ignored `local.env`, the certificate in its ignored
`signing/` keychain. Read them from the Mac when you need them. Never write the identifier,
the certificate's fingerprint, a home folder path or anyone's name into a tracked file, a
commit message or anything else that leaves the Mac.

In the main checkout, plain `./build.sh` signs with that identity. In a worktree, which
has neither file, sign with the main checkout's keychain where it is:

```bash
# The installed copy's identifier, and the main checkout's keychain.
ID="$(plutil -extract CFBundleIdentifier raw /Applications/MouseHerdr.app/Contents/Info.plist)"
MAIN="$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -1)"
KC="$MAIN/signing/mouseherdr.keychain-db"

BUNDLE_ID="$ID" SIGNING=adhoc ./build.sh
# codesign finds the identity only while the keychain is on the search list.
LOGIN="$(security login-keychain | sed 's/^ *"//; s/"$//')"
security list-keychains -d user -s "$LOGIN" "$KC"
security unlock-keychain -p mouseherdr "$KC"
CERT="$(security find-certificate -Z "$KC" | awk '/SHA-1 hash:/ {print $NF; exit}')"
codesign --force --keychain "$KC" --sign "$CERT" --identifier "$ID" dist/MouseHerdr.app
security list-keychains -d user -s "$LOGIN"   # take the keychain off the list again
codesign --verify --strict dist/MouseHerdr.app

# These two lines must be identical, or macOS will not apply the permissions to the build.
codesign -d -r- dist/MouseHerdr.app 2>&1 | grep designated
codesign -d -r- /Applications/MouseHerdr.app 2>&1 | grep designated
```

Do not copy `signing/` into a worktree, and do not let `build.sh` make a new identity
there with `SIGNING=local`: a different certificate loses the permissions.

Never leave the signing keychain on the search list. It is locked after a restart, and
anything that then reads the listed keychains makes macOS ask the owner for its password,
once per read. `./build.sh` lists it only while it signs. The steps above assume the
owner's list holds only the login keychain, so check `security list-keychains -d user`
before and after.

## Run a build on the owner's Mac

Only when the owner asks to see a build running. The build takes the mouse over from the
installed copy, which stays in `/Applications` as the way back.

```bash
pkill -x MouseHerdr                      # quits the installed copy, as build.sh does
while pgrep -x MouseHerdr >/dev/null; do sleep 0.2; done
open dist/MouseHerdr.app --args --show
tail -n 40 ~/Library/Logs/MouseHerdr.log
```

Read the log before saying that it works. A healthy start has a `mice:` and a
`following:` line and, for an MX Master 4 over Bluetooth, `found … open: 0x00000000`, a
`slots:` line and a `divert … ok` line for each captured control.

Then tell the owner:

- that the installed copy was quit and the build is running in its place;
- that the build points the login item at itself, and that opening the copy in
  `/Applications` again points it back;
- how to go back: quit MouseHerdr from its menu bar icon, then open it from Applications.
