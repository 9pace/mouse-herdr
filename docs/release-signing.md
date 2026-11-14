# Release signing

The public repository contains the build and release code. Signing credentials belong
in GitHub Actions environment secrets, never in Git or release assets. The public
certificate and publisher identity are included in the signed app; the private key is not.

## GitHub configuration

Create an environment named `release-signing`. Set its deployment branch policy to
**Selected branches and tags**, allowing only the **main branch**, with no tag rules.
Add these environment secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-encoded PKCS#12 export of the Developer ID Application certificate and its matching private key |
| `MACOS_CERTIFICATE_PASSWORD` | Strong password protecting that PKCS#12 export |
| `APPLE_ID` | Apple Account used for notarization |
| `APPLE_TEAM_ID` | Developer Program team identifier |
| `APPLE_APP_SPECIFIC_PASSWORD` | Dedicated app-specific password for notarization, generated in Apple Account settings |

Enter values through GitHub's secret settings or `gh secret set --env release-signing`
using standard input. Do not place secret values in command arguments, tracked files,
logs, issue comments, or pull requests. Export only the intended signing identity from
Keychain Access, not every key in the login keychain.

Only trusted changes should reach `main`, especially workflow and signing-script changes:
code running in a release job can use that job's secrets. Public pull requests run the
CI workflow without signing credentials. The release workflow accepts successful CI
runs for pushes to this repository's `main`, or a manual run on `main`; its planner also
checks the exact commit and current CI result before publishing.

## What a release does

1. Builds a universal app with ad-hoc signing.
2. Imports the Developer ID identity into a temporary keychain on a GitHub-hosted runner.
3. Signs with the hardened runtime and Apple's secure timestamp.
4. Submits the app to Apple's notary service and requires an `Accepted` result.
5. Staples and validates the notarization ticket, and checks Gatekeeper acceptance.
6. Deletes the temporary keychain and private-key export before packaging and publishing.
7. Verifies the signature, ticket, Gatekeeper result, versions, and architectures in the
   extracted release ZIP.

Missing credentials, rejected or timed-out notarization, and failed verification stop
the release. There is no fallback that publishes an unsigned app. A notary timeout can
leave a submission processing at Apple; retry the release after checking its status.

`scripts/sign_release.py` is a build input, so changing the signing behavior can produce
a release. Documentation and test changes alone do not. Local `./build.sh` behavior is
unchanged; use `SIGNING=adhoc ./build.sh` for disposable test builds.

## Credential maintenance

Keep the original private key in a secure local keychain and maintain an encrypted
backup. Renew the signing certificate before it expires and replace the two PKCS#12
secrets together. Rotate the dedicated app-specific password by replacing its GitHub
secret. Existing published assets are never overwritten.
