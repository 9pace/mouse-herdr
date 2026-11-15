# Telemetry design review

Reviewed 2026-11-15 against `feature/telemetry-design`, including the Swift app, settings,
catalog, mouse detection, ring/agent UI, update gate and build/test scripts.

## Verdict

**Revise before implementation; do not ship yet.** Opt-in, a small first-party payload and
no analytics SDK are sensible. The original anonymity promise was false, consent disclosure
was incomplete, and late-arrival accounting and several implementation assumptions conflicted.

The must-fix document corrections below are **applied to `telemetry-design.md`**. This is
not an implemented privacy control or a compliance sign-off: withdrawal/erasure, consent
evidence and the actual hosting/controller arrangements remain explicit launch blockers.
Only the two design documents change.

## Must-fix

1. **Describe pseudonymous data honestly — applied (§§1–6, 8).** A persistent UUID links
   daily behavior; its randomness does not make reports anonymous. The combined setup and
   exact counts can fingerprint an install even after reset. Replaced “anonymous”/“no
   personal information,” explained provider access to IP and arrival time, restricted raw
   access and joins, and prohibited public aggregates pending disclosure review. Receipt
   timestamps are day-only; provider logs, traces, backups and rate-limit state are covered.
   GDPR distinguishes pseudonymisation from anonymisation; online identifiers and reasonably
   available linkage matter, not just names. [1]

2. **Make opt-in informed and withdrawal actionable — applied as requirements/gates
   (§§5–6, 13).** Off by default is appropriate; Accessibility permission is not telemetry
   consent. The original prompt omitted the ID, mouse/settings/assignment data, processors
   and retention. Added accurate layered disclosure, controller identification, locally
   available notice, affirmative choice, notice-version evidence and renewed consent for
   expanded collection. Local wipe/90-day expiry does not resolve erasure after withdrawal.
   The no-network-while-off conflict now blocks release until an explicit offline-capable
   rights flow is agreed. Opt-in alone does not establish GDPR/ePrivacy compliance. [1–3]

3. **Complete reporting-window semantics — applied (§§4, 7, 8, 12).** A 7-day recomputation
   misses reports accepted up to 30 days late. Defined accepted dates, 30-day recomputation,
   the raw-history horizon, immutable idempotency, zero-event awake days, sleep/restart
   behavior, last-observed snapshots and clock rollback. WAU/28-day MAU count reporting IDs,
   not people. First opt-in is not a new installation; new-install/cohort retention metrics
   are explicitly deferred. Removed the unmeasurable opt-in-rate promise and the assertion
   that selection bias leaves trends/ratios reliable.

4. **Enforce a real sanitized schema — applied (§§3, 8–11).** “All strings are closed-list”
   was false for UUIDs, dates and versions; rejecting unknown keys contradicted ignoring
   unknown fields. Added typed/format validation, strict versioned schemas and no raw-body
   storage. Corrected `mxMaster3S`, unknown Herdr/transport states, and prohibited passing
   `Action`, `AgentInfo` or `AppState` into telemetry. Evidence:
   `Profiles/Catalog.swift:75`, `Agents.swift:183`, `MouseDetector.swift:13`,
   `Model.swift:105`, all under `Sources/MouseHerdr/`.

5. **Isolate lifecycle and failures — applied (§§4, 7, 9–11).** `App.swift:29` constructs
   `AppState` before developer flags are handled: eager telemetry initialization must be
   inert. Disable/reset must cancel pending work and reject stale completions, otherwise
   callbacks can restore wiped IDs/files or send old reports. Added consent checks before
   sends, bounded off-thread I/O, redirect refusal, owner-only files and no quit-time
   network wait. Existing `AppState` and `WindowDragger` are not `@MainActor`; the plan now
   requires explicit, compiler-checked boundaries instead of assuming those annotations.

6. **Align feature measurement with actual code — applied (§§3, 6, 10).** Documented why
   `default`, `agentWheel` and `dragWindow` are excluded from generic action counts;
   defined wheel bursts, recording success, other ring dismissals and typed-answer origin.
   Added `ContentView.swift`, `Updates.swift` and `Feel.swift` hooks and avoided counting
   drag cleanup or generic focus as user actions. Daily setup joins cannot identify the
   mouse responsible for each event. Evidence: `Model.swift:151`, `AppState.swift:752`,
   `:806`, `:936`, `:1024`, `Agents.swift:1782`, `ContentView.swift:365`,
   `Feel.swift:22`, `Updates.swift:137`. Settings placement was correct; `UpdateHelpPanel`
   actually lives in `UpdateViews.swift:72`.

7. **Resolve developer-test and transport contradictions — applied (§§7–12).**
   `Updates.swift:145–158` checks release metadata and Developer ID signing, so a nonrelease
   endpoint override cannot exercise a release-only sender. Replaced it with injected
   synthetic test transport/harness; retained production guards and explicitly disabled
   forced-home runs even with saved consent. Defined one daily send cycle plus retries,
   exact `202` acknowledgement, rejection behavior and uncompressed size limits.
   The proposed preview flag is clearly future work, requiring an AGENTS.md update.

## Should-fix

- **Collect less in v1.** Start with active reporting IDs and a few daily used/not-used
  feature flags. Require a named product decision for language, complete assignments,
  permissions, agent-count buckets and every exact counter. Remove the constant `build`
  field. This reduces fingerprinting and implementation effort more than elaborate
  anonymisation claims.
- **Simplify delivery.** Seven queued days can likely tolerate retrying on the next day's
  eligible send instead of five exponential attempts plus persisted retry deadlines.
  Keep a transport seam and fake clock; avoid a general scheduler/framework. Rotation,
  compression, public dashboards and per-profile counters should remain outside v1.
- **Specify the remaining bucket/query details before coding.** Define language fallback,
  haptic-strength thresholds, count/missing-value semantics, feature eligibility and
  minimum aggregate cells. The reviewed design identifies these decisions but is not an
  executable schema. “Field name appears in docs” tests do not prove payload parity;
  test validated example payloads and adversarial nested inputs.
- **Validate the real deployment.** No credentials, private signing identity, actual user
  identifiers or private home paths were found in the proposed telemetry documents; the
  sample UUID is illustrative and an ingest API key would provide no client secrecy.
  This is not a whole-history secret audit. Domain ownership, provider logs, access policy,
  transfers, deletion and request headers must be verified against the chosen deployment.

## Nice-to-have

- A small worked example with duplicate IDs, a reset and a 30-day-late report would make
  provisional/final WAU and MAU results easier to review.
- Once implemented, include a sanitized preview screenshot and one small network capture
  demonstrating the exact request fields and the absence of telemetry while disabled.

## Validation and sources

`git diff --check` passes. `scripts/test_release.py` passed 19 tests and
`scripts/test_sign_release.py` passed 11. `swift test` could not run because Swift is
unavailable; the ad-hoc build correctly refused Linux. The prescribed setup test invocation
failed because no macOS app binary exists (four macOS build tests skipped). No build was
installed or app launched. These documentation changes do not demonstrate runtime behavior.

Legal references describe the requirements used in this review; deployment-specific
application, national ePrivacy rules and unresolved rights flows still require review.

1. [GDPR, Regulation (EU) 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj):
   recitals 26/30; Articles 4, 5, 7, 13, 17, 25 and 32. Relevant original EU provisions
   were checked using the official National Archives copies:
   [definitions](https://www.legislation.gov.uk/eur/2016/679/article/4/adopted),
   [notice](https://www.legislation.gov.uk/eur/2016/679/article/13/adopted),
   [erasure](https://www.legislation.gov.uk/eur/2016/679/article/17/adopted) and
   [recitals](https://www.legislation.gov.uk/eur/2016/679/introduction/adopted).
2. [EDPB Guidelines 05/2020 on consent](https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-052020-consent-under-regulation-2016679_en),
   especially informed consent, demonstrating consent and withdrawal.
3. [EDPB Guidelines 2/2023, final technical scope of ePrivacy Article 5(3)](https://www.edpb.europa.eu/system/files/2024-10/edpb_guidelines_202302_technical_scope_art_53_eprivacydirective_v2_en_0.pdf).
   Terminal storage/access and GDPR processing are separate questions; random identifiers
   are not automatically exempt.
