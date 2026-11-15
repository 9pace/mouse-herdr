# Opt-in usage telemetry: design

Status: **draft, reviewed with corrections**. No code has been written. Nothing in this document is shipped.
See `telemetry-design-review.md`; the privacy launch gates in §5 and §13 remain unresolved.

MouseHerdr is a menu bar app that holds Accessibility and Input Monitoring permissions, and
its users are developers who care about privacy. `SECURITY.md` currently promises "The app
does not run a network listener or include telemetry". Any telemetry has to deserve that
trust: it collects little, says exactly what it collects, is easy to turn off, and is easy to
check.

## 1. Goals and non-goals

**Goals**

- Count **weekly and monthly reporting installs** (WAU/MAU). New-install and retention
  metrics need a separate cohort definition before implementation (§4).
- Learn **which features are used**, so that work goes where people actually are. One
  example: is the agent wheel used on mice other than the MX Master 4?
- Know the **environment we must support**: app version, macOS version, CPU architecture,
  which recognised mouse models are in use, and how they are connected.
- Keep it **simple** on the client and the server, with no third-party SDK.

**Non-goals**

- No crash reporting, logs, stack traces or performance tracing. That can be a separate design.
- No individual behaviour analysis or sessions. Reports are linkable by install id; stored
  report and receipt dates have day precision only.
- No A/B testing, remote config, feature flags or marketing attribution.
- No sale, advertising use or disclosure for others' independent purposes. Hosting
  processors necessarily handle reports and must be disclosed. No advertising identifiers.

## 2. What is never collected

The client must not read these into the telemetry module at all. Filtering them out
afterwards is not enough.

- Names, emails, account names, the macOS user name, the computer's host name.
- IP addresses in the payload. The receiving infrastructure necessarily sees the source
  IP and connection time; IPs must not enter analytics storage or persistent logs (see §8).
- File paths, app names or bundle ids, including the target of an "Open an app" action.
- Window titles, workspace, space, tab or agent names, agent questions or answers, typed
  text, recorded shortcut keys, or any keystrokes.
- Device names reported by mice. A Bluetooth mouse is often named after its owner
  ("Alex's MX Master").
- Hardware serials, MAC addresses, the hardware UUID, the IOPlatformUUID, or any other id
  that comes from the machine.
- Raw vendor and product ids of mice that are **not** in MouseHerdr's catalog.
- Exact times of day, time zones, screen sizes, or any other high-entropy value that could
  be used to fingerprint a Mac.

## 3. What is collected

Each report covers one UTC day on which the opted-in app was observed running and awake.
Categorical fields use closed enums; counts are bounded integers. UUIDs and UTC dates use
strict formats, and versions use bounded numeric components (no branch, commit or suffix).
Unknown categorical values map to a documented bucket; raw runtime strings never pass through.
Validate the same schema on client and server, including object keys and nested values.

**Privacy classification:** these are pseudonymous personal data, not anonymous reports.
A stable UUID permits singling out an install. Even without it, combinations of mouse,
versions, language, assignments, settings and exact daily counts can be distinctive and
linked to public bug reports. Closed enums and daily dates do not prevent that. Access to
raw rows is restricted (§8); do not join them to support, release-download or account data.
Each field needs a concrete decision it supports; prune unjustified fields before launch.

### 3.1 Environment

| Field | Example | Why |
| --- | --- | --- |
| `app_version` | `"1.0.47"` | Which releases are in use, and when old ones can be dropped. |
| `build` | `"release"` | Source builds never send in v1 (§9); remove this constant field if it serves no query. |
| `os_version` | `"26.1"` | major.minor only, to decide the minimum macOS. |
| `arch` | `"arm64"` / `"x86_64"` | The release is universal; is Intel still worth testing? |
| `language` | `"en"` | Two-letter UI language only, to decide whether translation is worth doing. The **region is not sent** (see §13). |

### 3.2 Setup

These are the last observed configuration for the day. Joining them to daily feature
counts shows an association, not which mouse produced an event when the selection changed.
Per-profile usage attribution is deferred rather than adding another counter dimension.

| Field | Values |
| --- | --- |
| `mouse.profile` | The selected catalog profile id, such as `"mxMaster4"`, `"mxMaster3S"` or `"magicMouse"`, or `"receiver"` or `"fallback"`. It can be manually selected, not verified hardware identity. Never the device name, and never the ids of an unknown mouse. |
| `mouse.transport` | `"bluetooth"`, `"usb"`, `"none"` (no followed device), `"unknown"` (other/empty transport). Normalize outside telemetry. |
| `mouse.direct_link` | `true` when the HID++ link is up |
| `mouse.connected_count` | The number of mice connected, capped at `"3+"` |
| `permissions` | `accessibility`, `input_monitoring`: booleans |
| `herdr` | `"unknown"`, `"missing"`, `"stopped"`, `"running"` |
| `agents_bucket` | The number of agents seen: `"0"`, `"1-3"`, `"4-10"`, `"11+"` |
| `settings` | Booleans for `haptics`, `feel_hover`, `feel_edges`, `snap_windows`, `ring_on_tap`, `feel_agents`, `launch_at_login` and `auto_updates`. Also `ring_order` (`"recent"` or `"space"`) and `haptic_strength_bucket` (`"low"`, `"mid"` or `"high"`). |
| `assignments` | For each slot (`middle`, `modeShift`, `gesture`, `gestureUp`…`gestureRight`, `forward`, `back`, `thumbPanel`, `thumbWheel`): the **preset id** assigned. A recorded shortcut is sent as `"shortcut"` and an app as `"app"`, never the key or the path. |

### 3.3 Feature use

These are daily counters, kept on the Mac and sent once. They are counts only, with no
order and no times. Each count is capped at 10,000.

| Counter key | Incremented when |
| --- | --- |
| `action.<presetId>` | A button runs a preset from `Catalog.groups`: `back`, `forward`, `prevTab`, `nextTab`, `newTab`, `closeTab`, `reopenTab`, `missionControl`, `appExpose`, `showDesktop`, `apps`, `spaceLeft`, `spaceRight`, `switchApp`, `spotlight`, `copy`, `paste`, `cut`, `undo`, `redo`, `playPause`, `nextTrack`, `prevTrack`, `volumeUp`, `volumeDown`, `mute`, `screenshot`, `screenshotTools`, `lock`, `middleClick`, `none`. Also `shortcut` and `app`, with no detail. |
| `gesture.<up\|down\|left\|right\|click>` | A gesture-button gesture fires |
| `wheel_mode.<wheelVolume\|wheelTabs\|wheelZoom\|wheelDesktops\|wheelUndo>` | The thumb wheel is rolled in that mode. Count once at the start of a burst after at least 350 ms without a delta, matching the existing gap in `thumbWheel(_:)`; do not send deltas or timing. |
| `window.drag` | A window drag ends |
| `window.snap.<half\|full\|quarter>` | A drag ends in a snap |
| `ring.open.<thumb_tap\|button\|menu\|window>` | The agent wheel opens, and how it was opened |
| `ring.pick.<centre\|wedge>` | An agent is opened from the wheel |
| `ring.close.<escape\|right_click\|trigger\|other>` | The wheel is put away without a pick or answer; `other` covers pointer-away/outside-click dismissal. Transition into a typed reply is not a dismissal. |
| `ring.pin` | An agent is pinned or unpinned, from the wheel or the Agents page |
| `answer.<option\|typed>` | An answer is submitted: options from the bubble or Agents page, typed replies from the ring's reply box. Count the submission, not successful delivery; never the content. |
| `agents_page.open_agent` | An agent is opened from the Agents page |
| `mouse.picker_changed` | A model is chosen by hand under **Change…** |
| `shortcut.recorded` | A shortcut is recorded. The key itself is never sent. |
| `window.opened` | The main window is opened |
| `update.restart` | **Restart to Update** is used |

The list is an `enum TelemetryCounter: String, CaseIterable`. The server rejects any key it
does not know. Adding a counter means changing code, `docs/telemetry.md` and the server's
allow-list together.

The action list intentionally excludes `Catalog.groups` entries `default`, `agentWheel`
and `dragWindow`: passthrough has no action count; ring opens and actual drags use their
dedicated counters. `none` counts an intercepted no-op. Assignments additionally allow those
three ids and `Catalog.wheelModes` ids. An unrecognized assignment maps to `"unknown"`.
Count successful shortcut assignment, not `beginRecording()` (Escape cancels).
Only fixed enum events and sanitized setup values cross into telemetry; never `Action`,
`AgentInfo`, `AppState`, device objects, key events or window rectangles.

## 4. The pseudonymous install id and WAU/MAU

- On the first report after telemetry is turned on, the client makes a **random UUID v4**
  (`UUID()`) and keeps it in `UserDefaults` as `telemetryInstallID`. It is not derived from
  the hardware, the user or any other id. It is not in the Keychain, so it does not survive
  a full uninstall with `defaults delete`.
- **Reset:** **Reset Statistics ID** cancels pending sends and clears counters/queue before
  replacing the UUID. It never relabels old reports with the new id or sends an old/new pair.
  Reset does not erase server rows, and distinctive fields can still link the two ids.
- **Disable means wipe:** turning telemetry off deletes the install id, the counters and
  the queue. Turning it back on starts a new id, which can inflate distinct-install counts.
  Wiping local state does not erase server rows; the withdrawal/erasure design is a launch
  gate (§5).
- **No automatic rotation in v1.** This preserves distinct counts across rolling windows,
  at the cost of persistent linkability. The UUID is not an anonymity guarantee. See §13.

**How the server computes reporting installs**

- One immutable report per id per observed awake day, including days with zero feature
  events. A report carries `day`; the server adds only `received_day`, never an exact receipt
  timestamp. Aggregates use `day`, so a report that waited in the
  queue while the Mac was offline still counts toward the right day.
- `DAU(d)` = the number of distinct `install_id` with a report for day `d`.
- `WAU(d)` = the number of distinct `install_id` with a report in `[d-6, d]`.
- `MAU(d)` = the number of distinct `install_id` with a report in `[d-27, d]`. This is a
  28-day window, which avoids bias from weekdays and the uneven lengths of months.
- On UTC receipt day `R`, accept only completed days in `[R-30, R-1]`; reject future,
  current-day and older reports. The nightly job recomputes **all last 30 completed days**,
  including DAU, WAU, MAU, feature and environment aggregates, after ingest for the job's
  cutoff. Recomputing MAU for `R-30` needs raw rows back to `R-57`, within the 90-day policy.
  Recent results remain provisional until that day's 30-day arrival window closes.
- Counts measure opted-in reporting ids, not people or all installs. Resets and multiple
  macOS users can inflate them; cloned preferences, lost queues, crashes and never reopening
  the app can undercount. Opt-in selection can bias both trends and feature ratios.
- **New installs and retention are deferred in v1.** First report means first observed
  opt-in, not installation; raw expiry loses first-seen history. Before adding these metrics,
  define bounded cohort storage, late first reports, resets, return windows and denominators.

## 5. Consent: off by default, asked once

**Recommendation: opt-in (off by default).** The reasons:

1. The app holds powerful permissions, and its public promise is that it has no telemetry.
   Turning on reporting silently in an update would break that promise.
2. Optional analytics storage/access must be assessed under national implementations of
   ePrivacy Article 5(3), separately from GDPR. Do not assume an exemption for a random id.
   This design uses prior opt-in globally and consent as its GDPR basis.
3. Developers inspect their network traffic. An unannounced connection to a new domain
   would be found and resented, and would cost more trust than the data is worth.
4. The cost is fewer reports and selection bias, including in trends and ratios. With id
   resets, counts are not even a strict lower bound on actual installs.

**Launch gates:** before enabling collection, publish a versioned privacy notice identifying
the controller and contact, purpose and legal basis, all data categories, processors/hosting
locations and transfer safeguards, retention (including backups), and rights/complaint routes.
Make it available offline before consent; opening GitHub must be a deliberate external link.
The controller's public identity must appear beside the prompt/toggle, not just behind a link.
Do not fill this draft with private addresses or signing-identity details.

Record the accepted notice version and affirmative choice, with day-level evidence of when
it occurred. Define the minimum server-verifiable consent record and its retention before
implementation; `telemetryAsked` alone is not proof of consent. Materially expanded collection
or a new purpose needs fresh consent before collection; refusal never reduces app functionality.

**Withdrawal and erasure are a release blocker:** off stops collection immediately, but
90-day expiry is not a substitute for erasure when consent is withdrawn and no other lawful
ground applies. Define an equally easy in-app withdrawal/erasure flow, ownership proof without
collecting names/emails, offline completion, backup expiry and handling of in-flight reports.
Resolve the conflict with "no network while off" explicitly: any narrowly scoped erasure
request must be disclosed and separated from usage reports, or use a reviewed alternative.
Until that contract is settled, do not ship the consent UI or make a deletion promise.

**First-run and upgrade notice.** Ask once, at a calm moment: not on the very first launch,
when permissions are the priority, and not while a permission is still missing.

- **When:** on a quiet start after both Accessibility and Input Monitoring are granted.
  Coordinate with `explainMenuBar()`, mouse notices and **What's New** in `App.swift`;
  wait until competing notices/windows have actually closed. The existing Accessibility-only
  startup check is not sufficient.
- **How:** a popover under the menu bar icon, in the same style as the existing menu bar and
  mouse notices:

  > **Help improve MouseHerdr?**
  > Share daily feature counts and setup information, including mouse model, settings,
  > language and software versions. A random statistics ID links your reports. Reports
  > are kept for up to 90 days. No names, file paths, window titles, typing or conversations.
  > Our hosting provider sees your IP to receive reports; it is not kept in analytics.
  > Optional; turn off in Settings at any time.
  > [Share usage statistics]  [No thanks]   *Privacy details…*

- Either answer or dismissal sets `telemetryAsked = true`; do not nag again for that notice version.
  Closing the popover leaves telemetry off. No preselected consent or consent keyboard
  default. The choice can be changed at any time in Settings.

**When telemetry is off:** no network request of any kind is made by the telemetry module,
no counters are kept, and any queued reports and the install id are deleted at once.

## 6. The Settings toggle

Settings is `SettingsPage` in `Sources/MouseHerdr/UpdateViews.swift`. It has a **General**
card, a **Software updates** card, and a footer with the version. A new **Privacy** card goes
**between "Software updates" and the version footer**, in the same style as the other cards
(`.regularMaterial`, corner radius 16, padding 18):

```
[hand.raised]  Privacy
[ ] Share usage statistics
    [The disclaimer below, wrapped to fit.]
    ─────────────
    [Show What's Sent…]   [Reset Statistics ID]          Privacy details…
```

- Toggle label: **Share usage statistics**
- Disclaimer (draft pending the withdrawal gate in §5): *"Helps prioritize features and
  supported devices. Sends daily feature counts, mouse and connection details, settings and
  assignment types, permission status, Herdr status and agent-count range, app/macOS versions,
  chip type and language. A random statistics ID links reports, kept for up to 90 days.
  No names, file paths, window titles, typing or conversations. Our hosting provider sees
  your IP to receive reports; it is not kept in analytics. Off unless you turn it on.
  Turn off any time in Settings."*
- **Show What's Sent…** opens a sheet with the pretty-printed JSON of today's report and of
  everything queued: the same serialized fields/values as sending, with added whitespace.
  Today's report is labelled incomplete and changes until finalized. While off, show no
  collected data; do not create an id or read setup to populate the preview.
- **Reset Statistics ID** is disabled while telemetry is off; explain that it is not erasure.
- **Privacy details…** opens the bundled notice, including the withdrawal/erasure route;
  an explicit **What's collected ↗** link opens `docs/telemetry.md` on GitHub.
- When telemetry is forced off by an environment variable or a managed preference (§9), the
  toggle is shown off and disabled, with the note *"Turned off by MOUSEHERDR_TELEMETRY."*
  or *"…by DO_NOT_TRACK."*, or *"Turned off by your administrator."* for MDM.

The side panel for Settings (`UpdateHelpPanel` in `UpdateViews.swift`, used by `ContentView`) gets one more line under
the update text: "Usage statistics are off unless you turn them on in Privacy."

## 7. Reports, sending, queue and failures

### 7.1 Example payload

```json
{
  "schema": 1,
  "install_id": "3f0c9a52-1b7e-4d8e-9a43-0c2b5f6e7d18",
  "day": "2026-11-14",
  "env": {
    "app_version": "1.0.47",
    "build": "release",
    "os_version": "26.1",
    "arch": "arm64",
    "language": "en"
  },
  "setup": {
    "mouse": { "profile": "mxMaster4", "transport": "bluetooth", "direct_link": true, "connected_count": "1" },
    "permissions": { "accessibility": true, "input_monitoring": true },
    "herdr": "running",
    "agents_bucket": "4-10",
    "settings": {
      "haptics": true, "haptic_strength_bucket": "mid", "feel_hover": true, "feel_edges": true,
      "snap_windows": true, "ring_on_tap": true, "feel_agents": true, "ring_order": "recent",
      "launch_at_login": true, "auto_updates": true
    },
    "assignments": {
      "middle": "default", "modeShift": "missionControl", "gesture": "agentWheel",
      "forward": "forward", "back": "back", "thumbPanel": "dragWindow", "thumbWheel": "wheelTabs"
    }
  },
  "counters": {
    "ring.open.thumb_tap": 41,
    "ring.pick.centre": 22,
    "ring.pick.wedge": 12,
    "ring.close.escape": 7,
    "answer.option": 9,
    "action.missionControl": 18,
    "action.back": 130,
    "window.drag": 25,
    "window.snap.half": 6,
    "wheel_mode.wheelTabs": 54
  }
}
```

Requests are sent as `POST` with `Content-Type: application/json`. The body is
`{"reports": [ … up to 7 reports … ]}`.

### 7.2 Cadence

- Counters build up in memory and are saved to disk every 5 minutes and on quit, so that a
  crash loses little.
- Mark observed awake days at launch, wake, feature events and a lightweight daily timer.
  Finalize the previous observed day before counting on a new day; never invent intervening
  days after sleep/quit. Retain each day's last sanitized setup/version snapshot, rather
  than attaching today's setup to an old day. Persist current-day state across restarts;
  quit saves it without sending a partial day. Finalize on the next rollover/launch.
- Start at most **one send cycle per UTC day**, with a random wait of 0 to 60 minutes.
  Launch/backlog/wake share that budget; retries belong to that cycle (§7.3). Persist its
  day, attempt count and retry deadline across restarts. Jitter smooths load, not identity.
- Clock rollback must not reopen a finalized day or duplicate counts; resume new reports
  when the clock catches up. Days never observed awake produce no report.

### 7.3 Offline queue and retries

- The queue is a JSON file in `~/Library/Application Support/MouseHerdr/telemetry-queue.json`,
  written atomically.
- It holds at most **7 reports**. When it is full, the oldest is dropped. Reports older than
  30 days are dropped without being sent.
- Retries happen on a network error, a timeout, `429` or `5xx`. They back off exponentially
  from 1 minute, doubling to a 6-hour maximum, with jitter, and stop after 5 attempts. The
  next day's send tries again. A `429` or `503` with `Retry-After` is honoured.
- On a `4xx` other than `429`, the batch is dropped and not retried, and one line goes to
  the log.
- A report is removed on `202`, a permanent rejection above, expiry, overflow or a local
  wipe. Other unexpected `2xx` responses retain the batch under the bounded retry policy.

### 7.4 Limits

- One report must be **4 KB or less** before compression. A report that is larger is a bug:
  it is dropped and logged.
- One request must be **32 KB or less**, uncompressed in v1.
- The server rejects bodies over 32 KB and unsupported content encodings before parsing,
  and enforces the 7-report cap, depth limits and bounded field lengths.

### 7.5 Failure must never affect the app

- A `URLSession(configuration: .ephemeral)` with no cookies, no cache and no credential
  storage. Encoding, disk I/O and networking run off the main thread at utility priority,
  with 15-second request and resource timeouts and `waitsForConnectivity = false`.
  Refuse redirects and authentication challenges; bound/discard response bodies.
- Event/HID/ring callbacks do only a guarded in-memory enum increment on their existing
  main-thread path. No I/O, encoding, waiting or exception escapes to the caller.
- Construction is inert. Normal startup checks eligibility and effective consent before
  activation; when off, it may only wipe previously saved telemetry state. Developer paths
  never activate or mutate it. Disable, reset and effective kill switches cancel timers,
  requests and scheduled writes. A
  generation token makes stale completions unable to retry or recreate wiped state.
  Bytes already transmitted cannot be recalled; erasure must cover that race (§5).
  Recheck effective consent immediately before each send. Never wait for network on quit.
- No UI ever shows a telemetry error. A failure writes at most one log line per day
  (`telemetry: send failed (status 503), 3 queued`). The payload is never logged.
- If the disk file is corrupt/oversized, discard it before unbounded decoding. Unwritable
  storage fails closed for persistence/sending without disrupting the app. Counter, queue
  and temporary files are owner-only; normal log lines never contain ids or raw errors.

## 8. Endpoint and server

The proposed endpoint is `https://telemetry.mouseherdr.dev/v1/reports`, subject to ownership
and hosting verification before it becomes a Swift `URL(string:)` constant. HTTPS is required.
There is no runtime endpoint override. Tests inject a transport and, for integration tests,
a dedicated synthetic-data harness injects a local/staging endpoint without starting the app.
There is **no API key**: the app is public, so any key would be public, and abuse is handled
by validation and rate limits instead.

### 8.1 Client contract

| | |
| --- | --- |
| Request | `POST /v1/reports`, JSON body `{"reports":[Report…]}`, fixed `User-Agent: MouseHerdr-Telemetry/1`; no locale, OS/build detail, authentication, cookies or device headers |
| `202 Accepted` | Every report was stored, or was a duplicate. The client drops the batch. |
| `400` / `413` / `422` | The batch is malformed or too large. The client drops it. |
| `429` / `503` | Try again later. `Retry-After` is honoured. |
| other `5xx`, network error | Retry with backoff (§7.3) |
| Idempotency | `(install_id, day)` is the key. First accepted immutable report wins; exact duplicates are acknowledged without rewriting. A conflicting duplicate rejects the batch with `422`. Validate the entire batch before an atomic insert/acknowledgement. |

The client sends no cookies, no authentication and no device headers. Old app versions must
keep working, so the server retains validators for supported `schema` versions. Reject
unknown fields/keys/values rather than persisting or logging them. New fields require a new
schema deployed server-first; do not echo rejected content in errors.

### 8.2 Recommended minimal backend (vendor-neutral)

- **Ingest:** one stateless HTTPS function behind the domain. It checks the schema against
  the allow-list of keys and values, caps sizes, and writes one row per report:
  `(install_id, day, schema, payload_json, received_day)`, using the idempotency rule above.
  Serialize the validated typed report, never the raw request body.
- **Store:** a small SQL database. Any managed Postgres or SQLite-compatible service will do.
- **Aggregate:** a nightly job fills tables such as `daily_active(day, count)`,
  `wau(day, count)`, `mau(day, count)`, `feature_daily(day, key, installs, total)` and
  `env_daily(day, field, value, installs)`. A private dashboard reads only these aggregates.
  Feature adoption uses distinct ids with counter > 0 over reporting ids eligible for that
  feature/schema; label unavailable counters separately from zero use.
- **Retention:** delete raw rows by **report day + 90 days**, not by last receipt/retry.
  Backups/replicas must meet the same deletion deadline. Aggregate retention also needs a
  limit and disclosure review: removing ids alone does not anonymize sparse cells.
- **Access:** ingest has write-only application privileges; aggregate jobs have only needed
  access. Restrict raw access to named operators, keep exports private, and encrypt storage
  and backups. No public dashboard or raw downloads in v1; set small-cell suppression and
  cross-filter/differencing rules before any later publication.
- **IP handling:** infrastructure sees the IP and precise arrival time. Neither may be
  retained with reports. Rate-limiting uses volatile IP buckets expiring within an hour:
  - access/request logging and tracing are off at edge, function, WAF and database layers,
    or exclude client addresses, bodies, identifiers and exact per-report timestamps;
  - `X-Forwarded-For` and the like are not stored or forwarded to storage;
  - there is no geo-IP lookup;
  - rate-limit state is not persisted, exported or joined to analytics.

  This must be verified against the provider's own security logs, subprocessors and defaults
  before launch. If the provider cannot meet it, change provider or revise the notice and
  legal assessment before collecting anything; do not promise an unverified zero-log policy.
- **Abuse:** a limit of 60 requests per hour per IP at the edge, and the server rejects keys
  it does not know. Fake reports can inflate counts. That is an accepted risk for
  opt-in statistics. Add an overall ingest/storage budget and reject reports outside §4's
  date range; per-IP limits alone neither stop id farming nor protect shared NAT users.

## 9. Transparency and kill switches

- **`docs/telemetry.md`** is a user-facing page listing every field and counter in §3, with
  its type and allowed values. It also gives the retention, the IP policy, and how to check
  and turn off telemetry. It is linked from the README ("Good to know"), from `SECURITY.md`
  and from Settings. A unit test checks that every `TelemetryCounter` case and every report
  field appears on that page (§11).
- **Verifying:**
  - **Show What's Sent…** in Settings.
  - `MouseHerdr --telemetry-preview` is a proposed one-job developer flag. It reads only
    existing report state, never generates an id, writes files, starts the sender or captures
    input; an empty home prints `{"reports":[]}`. Add it to AGENTS.md's approved flag list
    when implemented; it does not exist in today's binary.
  - The log records `telemetry: sent 2 reports (1.9 KB)` with no content.
  - The source is public.
- **Turning it off without the UI:**
  - `defaults write dev.mouseherdr.app telemetryEnabled -bool false` (substitute a custom
    identifier).
  - The environment variable `MOUSEHERDR_TELEMETRY=0` forces it off. `DO_NOT_TRACK=1` is
    also honoured.
  - A managed preference (MDM profile) setting `telemetryEnabled = false` forces it off and
    greys out the toggle. Detect forced preferences, rather than treating every local false
    value as managed. Managed true never supplies the user's consent.
- **Off for CI and development:** telemetry only ever sends from a **release bundle**
  (`UpdateManager.isReleaseBundle`). Source builds, ad-hoc builds, `swift test`, snapshots and
  every one-job developer path (`--snapshot*`, `--detect-mice`, `--identify`, `--list-mice`,
  `--herdr-status`, `--version`, `--telemetry-preview`) never activate telemetry. Explicitly
  force it off whenever `CFFIXED_USER_HOME` is present, even if that home contains consent.
  `AppState` is constructed before flags are handled, so initialization must remain inert.
  Test harness injection must not bypass these production startup guards.
- Sparkle's own system profiling (`SUEnableSystemProfiling`) stays **off**. It is not part
  of this design.

## 10. Implementation plan (Swift client)

| File | Change |
| --- | --- |
| `Sources/MouseHerdr/Telemetry.swift` *(new)* | `TelemetryPreferences` (enabled, asked, notice version/consent evidence, install id, forced-off reason; takes `UserDefaults` like `UpdatePreferences`); `enum TelemetryCounter`; in-memory counters; `TelemetryReport: Codable` accepting only sanitized value types; bounded queue, sender behind `TelemetryTransport`, and inert `Telemetry: ObservableObject` with an injected clock/scheduler. Private serial worker owns encoding and disk/network I/O. |
| `Sources/MouseHerdr/TelemetryViews.swift` *(new)* | The Privacy card, the "What's sent" sheet and the consent popover content. |
| `Sources/MouseHerdr/UpdateViews.swift` | Add the Privacy card to `SettingsPage`, and the extra line in `UpdateHelpPanel`. |
| `Sources/MouseHerdr/AppState.swift` | Inert telemetry owner. Enum-only counts in `perform(_:)`, `toggleWheel`/`openRing` (carry trigger), `togglePin`, `answer`, `swipe`/`gestureUp`, `thumbWheel`, `choose(_:)` and successful shortcut assignment. `telemetrySnapshot()` sanitizes setup outside telemetry. |
| `Sources/MouseHerdr/Agents.swift` | Emit enum-only wheel picks and dismissal reasons at actual UI outcomes. Capture centre/wedge before `close()` resets `onHub`; count typed submissions through the existing reply callback once. |
| `Sources/MouseHerdr/ContentView.swift`, `Sources/MouseHerdr/Updates.swift` | Carry Agents-page focus/window trigger origins at their call sites; count `restartToUpdate()` only after its ready guard. Do not count generic agent focus as an Agents-page action. |
| `WindowDragger` (in `AppState.swift`), `Sources/MouseHerdr/Feel.swift` | `Snap.zone` currently returns a rectangle; expose a coarse snap kind outside telemetry. `end(snap:)` counts only an actual active drag and applied snap, not cleanup calls from begin/shutdown. |
| `Sources/MouseHerdr/App.swift` | Activate only after normal-start eligibility and consent checks; coordinate consent notices. Handle read-only `--telemetry-preview` without activating app services. Count actual `showWindow()` transitions. Persist on quit without network wait. |
| `build.sh`, `AGENTS.md` | Bundle the versioned privacy notice; document the implemented safe preview flag. Retain the existing release marker/signature gate. |
| `docs/telemetry.md` *(new)*, `README.md`, `SECURITY.md` | The field list. A "Usage statistics" paragraph. Replace "does not include telemetry" with an accurate sentence and a link. |
| `Resources/ReleaseNotes.md` | A What's New entry for the release that adds it. |

Notes:
- The client needs no new dependencies (Foundation `URLSession` and `JSONEncoder`).
- Existing `AppState`/`WindowDragger` are not `@MainActor`. Keep increments main-thread
  confined and verify callback delivery; explicitly bridge any new actor boundary under
  the project's Swift 5 mode. Pass immutable sanitized values to the private worker, never
  capture live `AppState` there. No telemetry-specific HID scheduling or blocking dispatch.

## 11. Testing plan

- **Unit tests** in `Tests/MouseHerdrTests/TelemetryTests.swift`, using a `UserDefaults` suite
  per test as `UpdateTests` does, and a fake transport:
  - It is off by default, and nothing is sent or counted while it is off.
  - Turning it off deletes the id, the counters and the queue. After re-enabling, the first
    report creates a new UUID; the initial toggle itself creates none.
  - The environment, forced-home and managed kill switches win over the toggle. Disable/reset
    during a request, timer or pending disk write cannot resurrect old ids/data or retry.
  - Report contents: a profile with a personal device name produces only the catalog id. An
    `app` or `shortcut` action produces only its kind. Snapshot test: no string in an
    encoded report escapes the field's enum/format/size rules (walk keys as well as values).
    Test unknown transport/Herdr states, malformed versions and adversarial nested fields.
  - Day rollover, the queue cap and expiry, retry and backoff for each status code, and
    idempotent resends, zero-event days, sleep/wake, clock rollback, restarts and old snapshots.
  - Server: distinct-id windows and a report 30 days late update every affected aggregate;
    reject future days, conflicting duplicates and unknown fields without storing/logging them.
    Verify expiry/backups, consent/erasure races and provider logging before live collection.
  - Each report is 4 KB or less with every counter at its maximum.
  - `docs/telemetry.md` mentions every `TelemetryCounter` case and every field name.
- **`scripts/test_setup.py`:** `--telemetry-preview` runs with an empty home folder, prints
  `{"reports":[]}`, sends nothing, changes no files and exits 0. Every other developer path
  makes no telemetry request even with consent seeded into its test home. Test sender behavior
  using an injected fake transport and synthetic harness; do not add a runtime release-gate
  bypass. Verify actual request headers, redirect refusal and production gating on macOS.
- **Snapshot:** add `--tab settings` with the Privacy card, in light and dark, to the review
  screenshots.
- **Manual:** watch with Little Snitch or `nettop` that there are no connections while it is
  off, and one send cycle a day (possibly multiple retry POSTs) while it is on. Pull the network, check that the queue fills
  and later drains, and that the app stays responsive with the endpoint unreachable or
  blackholed.

## 12. Rollout

1. **Design review** of this document, and the owner's answers to §13.
2. **Server first:** after resolving §5/§13 launch gates, deploy ingest and storage, verify
   the full logging/retention policy, and send synthetic test reports only.
3. **Client tests:** exercise an injected synthetic-data harness against local/staging
   ingest. Normal source/ad-hoc app runs remain unable to send; a hidden Settings card is
   not a consent or privacy control.
4. **Release N:** ship the Settings card, the consent popover, `docs/telemetry.md` and the
   updated `SECURITY.md`. Announce it in What's New and in the release notes.
5. **After 2 to 4 weeks:** check reporting volume, data quality and payload sizes, then prune
   unused counters. Opt-in rate is not measurable without a denominator of all eligible users;
   do not add reporting from nonconsenting users to obtain one.

## 13. Open questions

1. **Value of opt-in data.** Is the biased reporting population useful enough to justify
   telemetry? Opt-out is not an interchangeable default under this consent-based design.
2. **Region.** Send a coarse region (continent, or the region from the macOS locale), or
   only the language? The current proposal is language only. A region adds a little
   fingerprinting surface and answers no question we have yet.
3. **ID rotation.** Is stable-id linkability justified? Rotation limits direct id linkage
   but does not eliminate fingerprinting and can inflate reporting-id counts across a window.
4. **Withdrawal/erasure (launch blocker).** Settle §5's network-while-off conflict, local
   proof/identifier lifetime, offline completion, forced-off cases and stale in-flight reports.
   Retention expiry alone does not resolve it.
5. **Source builds.** Should source builds be able to opt in (with `build: "source"`), or
   never send at all?
6. **Unknown mice.** Would a count of unknown vendor ids (no product ids) be worth sending,
   to decide which mice to add to the catalog? Or should that stay with GitHub issues?
7. **Server hosting (launch blocker).** Verify domain control, controller/contact, processors,
   agreements, jurisdiction/transfers, provider logs, raw access and backup deletion. The
   dashboard stays private in v1; any publication needs a separate disclosure assessment.
8. **Retention:** is 90 days of raw data right, or would 35 days do? MAU needs only 28 days
   plus late-report history: the current 30-day arrival window requires 58 report days.
   Shorter raw retention therefore requires shorter lateness or a different aggregation design.
9. **Minimization and metrics.** Which decisions justify language, the full assignment vector,
   permission/agent counts and exact counters? Prefer daily used/not-used for adoption.
   Define environment bucket thresholds, feature eligibility and cohort semantics before
   adding retention; do not silently extend id history.
10. **Consent evidence and rights (launch blocker).** Finalize minimal notice-version/choice
    evidence and its retention, and access/export/erasure handling without identity collection.
    Review the actual audience, including managed/shared Macs and applicability of children's
    consent rules, before claiming the flow is compliant.
