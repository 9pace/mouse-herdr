# Anonymous usage telemetry: design

Status: **draft for review**. No code has been written. Nothing in this document is shipped.

MouseHerdr is a menu bar app that holds Accessibility and Input Monitoring permissions, and
its users are developers who care about privacy. `SECURITY.md` currently promises "The app
does not run a network listener or include telemetry". Any telemetry has to deserve that
trust: it collects little, says exactly what it collects, is easy to turn off, and is easy to
check.

## 1. Goals and non-goals

**Goals**

- Count **weekly and monthly active installs** (WAU/MAU), new installs, and how many stay.
- Learn **which features are used**, so that work goes where people actually are. One
  example: is the agent wheel used on mice other than the MX Master 4?
- Know the **environment we must support**: app version, macOS version, CPU architecture,
  which recognised mouse models are in use, and how they are connected.
- Keep it **simple** on the client and the server, with no third-party SDK.

**Non-goals**

- No crash reporting, logs, stack traces or performance tracing. That can be a separate design.
- No tracking of a single user's behaviour over time, no sessions, no timestamps finer than a day.
- No A/B testing, remote config, feature flags or marketing attribution.
- No data sold or shared with third parties. No advertising identifiers.

## 2. What is never collected

The client must not read these into the telemetry module at all. Filtering them out
afterwards is not enough.

- Names, emails, account names, the macOS user name, the computer's host name.
- IP addresses. The server does not store or log them (see §8).
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

Each report covers one UTC day on which the app ran. Every field comes from a **closed list
of values defined in code**. There are no free-form strings, so nothing unexpected can leak
into a report.

### 3.1 Environment

| Field | Example | Why |
| --- | --- | --- |
| `app_version` | `"1.0.47"` | Which releases are in use, and when old ones can be dropped. |
| `build` | `"release"` / `"source"` | Separates downloaded releases from source builds. |
| `os_version` | `"26.1"` | major.minor only, to decide the minimum macOS. |
| `arch` | `"arm64"` / `"x86_64"` | The release is universal; is Intel still worth testing? |
| `language` | `"en"` | Two-letter UI language only, to decide whether translation is worth doing. The **region is not sent** (see §13). |

### 3.2 Setup

These are a snapshot of the configuration at the end of the day.

| Field | Values |
| --- | --- |
| `mouse.profile` | A catalog profile id such as `"mxMaster4"`, `"mxMaster3s"` or `"magicMouse"`, or `"receiver"` or `"fallback"`. Never the device name, and never the ids of an unknown mouse. |
| `mouse.transport` | `"bluetooth"`, `"usb"`, `"none"` |
| `mouse.direct_link` | `true` when the HID++ link is up |
| `mouse.connected_count` | The number of mice connected, capped at `"3+"` |
| `permissions` | `accessibility`, `input_monitoring`: booleans |
| `herdr` | `"missing"`, `"stopped"`, `"running"` |
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
| `wheel_mode.<wheelVolume\|wheelTabs\|wheelZoom\|wheelDesktops\|wheelUndo>` | The thumb wheel is rolled in that mode. Counted once per roll, not per notch. |
| `window.drag` | A window drag ends |
| `window.snap.<half\|full\|quarter>` | A drag ends in a snap |
| `ring.open.<thumb_tap\|button\|menu\|window>` | The agent wheel opens, and how it was opened |
| `ring.pick.<centre\|wedge>` | An agent is opened from the wheel |
| `ring.close.<escape\|right_click\|trigger>` | The wheel is put away without a pick |
| `ring.pin` | An agent is pinned or unpinned, from the wheel or the Agents page |
| `answer.<option\|typed>` | An agent question is answered from the bubble or the Agents page. Only that it happened is counted, never the content. |
| `agents_page.open_agent` | An agent is opened from the Agents page |
| `mouse.picker_changed` | A model is chosen by hand under **Change…** |
| `shortcut.recorded` | A shortcut is recorded. The key itself is never sent. |
| `window.opened` | The main window is opened |
| `update.restart` | **Restart to Update** is used |

The list is an `enum TelemetryCounter: String, CaseIterable`. The server rejects any key it
does not know. Adding a counter means changing code, `docs/telemetry.md` and the server's
allow-list together.

## 4. The anonymous install id and WAU/MAU

- On the first report after telemetry is turned on, the client makes a **random UUID v4**
  (`UUID()`) and keeps it in `UserDefaults` as `telemetryInstallID`. It is not derived from
  the hardware, the user or any other id. It is not in the Keychain, so it does not survive
  a full uninstall with `defaults delete`.
- **Reset:** the **Reset anonymous ID** button in Settings replaces it with a new UUID.
- **Disable means wipe:** turning telemetry off deletes the install id, the counters and
  the queue. Turning it back on starts a new id. That reads as a new install, which is an
  acceptable cost.
- **No automatic rotation in v1.** Rotating an id inflates WAU/MAU and new-install counts,
  and the id already carries no personal data. See §13.

**How the server computes active users**

- One report per install per day on which the app ran. A report carries `day` (a UTC date)
  as well as the time it was received. Aggregates use `day`, so a report that waited in the
  queue while the Mac was offline still counts toward the right day.
- `DAU(d)` = the number of distinct `install_id` with a report for day `d`.
- `WAU(d)` = the number of distinct `install_id` with a report in `[d-6, d]`.
- `MAU(d)` = the number of distinct `install_id` with a report in `[d-27, d]`. This is a
  28-day window, which avoids bias from weekdays and the uneven lengths of months.
- Because reports can arrive late, a nightly job recomputes the last 7 days.
- New installs = ids whose first day is `d`. Retention comes from first day versus later days.

## 5. Consent: off by default, asked once

**Recommendation: opt-in (off by default).** The reasons:

1. The app holds powerful permissions, and its public promise is that it has no telemetry.
   Turning on reporting silently in an update would break that promise.
2. A stored device identifier, even a random one, needs consent under the EU's ePrivacy
   rules. Opt-in avoids a geography-dependent default.
3. Developers inspect their network traffic. An unannounced connection to a new domain
   would be found and resented, and would cost more trust than the data is worth.
4. The cost is fewer reports. Counts become a lower bound, so the absolute numbers are
   biased, but the trends and the ratios (features, versions, architectures) are still useful.

**First-run and upgrade notice.** Ask once, at a calm moment: not on the very first launch,
when permissions are the priority, and not while a permission is still missing.

- **When:** on the first quiet start after Accessibility has been granted. That is the slot
  `explainMenuBar()` already uses in `App.swift`. For users upgrading, it comes on the first
  start after **What's New** has been shown for the release that adds telemetry.
- **How:** a popover under the menu bar icon, in the same style as the existing menu bar and
  mouse notices:

  > **Help improve MouseHerdr?**
  > Share anonymous usage statistics: which features are used, and your app and macOS
  > versions. No personal information, file names, window titles or typing, ever.
  > [Share anonymous statistics]  [No thanks]   *What's collected ↗*

- Either answer sets `telemetryAsked = true`, and the question is never asked again. Closing
  the popover counts as "No thanks". The choice can be changed at any time in Settings.

**When telemetry is off:** no network request of any kind is made by the telemetry module,
no counters are kept, and any queued reports and the install id are deleted at once.

## 6. The Settings toggle

Settings is `SettingsPage` in `Sources/MouseHerdr/UpdateViews.swift`. It has a **General**
card, a **Software updates** card, and a footer with the version. A new **Privacy** card goes
**between "Software updates" and the version footer**, in the same style as the other cards
(`.regularMaterial`, corner radius 16, padding 18):

```
[hand.raised]  Privacy
[ ] Share anonymous usage statistics
    Helps decide what to improve. Sends which features you use, your MouseHerdr and
    macOS versions and your Mac's chip type once a day. Never your name, files, window
    titles, typing, agent conversations or IP address. Off unless you turn it on.
    ─────────────
    [Show What's Sent…]   [Reset Anonymous ID]          What's collected ↗
```

- Toggle label: **Share anonymous usage statistics**
- Disclaimer (exact text): *"Helps decide what to improve. Sends which features you use,
  your MouseHerdr and macOS versions and your Mac's chip type once a day. Never your name,
  files, window titles, typing, agent conversations or IP address. Off unless you turn it
  on."*
- **Show What's Sent…** opens a sheet with the pretty-printed JSON of today's report and of
  everything queued: exactly the bytes that would be sent.
- **Reset Anonymous ID** is disabled while telemetry is off.
- **What's collected ↗** links to `docs/telemetry.md` on GitHub.
- When telemetry is forced off by an environment variable or a managed preference (§9), the
  toggle is shown off and disabled, with the note *"Turned off by MOUSEHERDR_TELEMETRY."*
  or *"…by DO_NOT_TRACK."*.

The side panel for Settings (`UpdateHelpPanel` in `ContentView`) gets one more line under
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
- When the UTC day changes, or at launch if the last report day is in the past, the finished
  day becomes a report and is added to the queue.
- The queue is sent **once per day at most**, after a random wait of 0 to 60 minutes. The
  random wait keeps a burst at midnight UTC or at release time from showing up as a pattern.
  It is also sent at launch when there is a backlog.
- Days on which the app did not run produce no report.

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
- A report is removed from the queue only on `2xx`.

### 7.4 Limits

- One report must be **4 KB or less** before compression. A report that is larger is a bug:
  it is dropped and logged.
- One request must be **32 KB or less**. Compressing it is optional (`Content-Encoding: gzip`).
- The server rejects bodies over 64 KB.

### 7.5 Failure must never affect the app

- A `URLSession(configuration: .ephemeral)` with no cookies, no cache and no credential
  storage. It runs at `.utility` QoS off the main thread, with a 15-second timeout, and
  `waitsForConnectivity = false`.
- No telemetry call can throw out to the caller, block the event tap, or touch the HID or
  ring code paths. Counting a feature is one in-memory increment on the main thread.
- No UI ever shows a telemetry error. A failure writes at most one log line per day
  (`telemetry: send failed (status 503), 3 queued`). The payload is never logged.
- If the disk file is corrupt, it is deleted and the queue starts again empty.

## 8. Endpoint and server

The endpoint is the constant `Telemetry.defaultEndpoint = URL("https://telemetry.mouseherdr.dev/v1/reports")`.
For non-release builds only, it can be overridden with the environment variable
`MOUSEHERDR_TELEMETRY_URL`, which is for testing against a local server. HTTPS is required.
There is **no API key**: the app is public, so any key would be public, and abuse is handled
by validation and rate limits instead.

### 8.1 Client contract

| | |
| --- | --- |
| Request | `POST /v1/reports`, JSON body `{"reports":[Report…]}`, `User-Agent: MouseHerdr/<version>` and no other identifying headers |
| `202 Accepted` | Every report was stored, or was a duplicate. The client drops the batch. |
| `400` / `413` / `422` | The batch is malformed or too large. The client drops it. |
| `429` / `503` | Try again later. `Retry-After` is honoured. |
| other `5xx`, network error | Retry with backoff (§7.3) |
| Idempotency | `(install_id, day)` is the key. A resent report replaces the first, so retries are safe. |

The client sends no cookies, no authentication and no device headers. Old app versions must
keep working, so the server accepts `schema` versions it knows and ignores fields it does
not know within those versions.

### 8.2 Recommended minimal backend (vendor-neutral)

- **Ingest:** one stateless HTTPS function behind the domain. It checks the schema against
  the allow-list of keys and values, caps sizes, and writes one row per report:
  `(install_id, day, schema, payload_json, received_day)`. It upserts on `(install_id, day)`.
- **Store:** a small SQL database. Any managed Postgres or SQLite-compatible service will do.
- **Aggregate:** a nightly job fills tables such as `daily_active(day, count)`,
  `wau(day, count)`, `mau(day, count)`, `feature_daily(day, key, installs, total)` and
  `env_daily(day, field, value, installs)`. A dashboard reads only these aggregates.
- **Retention:** raw rows are deleted after **90 days**. Aggregates are kept with no
  install ids in them.
- **IP handling:** the IP address is used only to route the TLS connection and for
  rate-limiting held in memory, never stored:
  - access logging is off at the edge and in the function, or logs drop the client address;
  - `X-Forwarded-For` and the like are not stored or forwarded to storage;
  - there is no geo-IP lookup;
  - any rate-limit buckets live in memory or a short-lived store and expire within an hour.

  This is stated in `docs/telemetry.md`. The owner should check the hosting provider's own
  default request logging and turn it off, because that is where an IP usually leaks.
- **Abuse:** a limit of 60 requests per hour per IP at the edge, and the server rejects keys
  it does not know. Fake reports can inflate counts. That is an accepted risk for
  anonymous statistics, and it can be watched for with sanity checks such as one id
  reporting implausibly many days.

## 9. Transparency and kill switches

- **`docs/telemetry.md`** is a user-facing page listing every field and counter in §3, with
  its type and allowed values. It also gives the retention, the IP policy, and how to check
  and turn off telemetry. It is linked from the README ("Good to know"), from `SECURITY.md`
  and from Settings. A unit test checks that every `TelemetryCounter` case and every report
  field appears on that page (§11).
- **Verifying:**
  - **Show What's Sent…** in Settings.
  - `MouseHerdr --telemetry-preview` prints the next batch as JSON and exits. It is a
    one-job developer flag, so it is safe to run beside the installed copy (see AGENTS.md).
  - The log records `telemetry: sent 2 reports (1.9 KB)` with no content.
  - The source is public.
- **Turning it off without the UI:**
  - `defaults write dev.mouseherdr.app telemetryEnabled -bool false` (substitute a custom
    identifier).
  - The environment variable `MOUSEHERDR_TELEMETRY=0` forces it off. `DO_NOT_TRACK=1` is
    also honoured.
  - A managed preference (MDM profile) setting `telemetryEnabled = false` forces it off and
    greys out the toggle.
- **Off for CI and development:** telemetry only ever sends from a **release bundle**
  (`UpdateManager.isReleaseBundle`). Source builds, ad-hoc builds, `swift test`, snapshots and
  every developer flag (`--snapshot*`, `--detect-mice`, `--identify`, `--list-mice`,
  `--herdr-status`) never start the telemetry module. Neither does a run whose home folder is
  set with `CFFIXED_USER_HOME`, because that has no consent recorded in it.
- Sparkle's own system profiling (`SUEnableSystemProfiling`) stays **off**. It is not part
  of this design.

## 10. Implementation plan (Swift client)

| File | Change |
| --- | --- |
| `Sources/MouseHerdr/Telemetry.swift` *(new)* | `TelemetryPreferences` (enabled, asked, install id, forced-off reason; takes `UserDefaults` like `UpdatePreferences`); `enum TelemetryCounter`; `UsageCounters` (in-memory, saved to disk); `TelemetryReport: Codable` and a builder that maps `AppState` into the closed value sets; `TelemetryQueue` (file, cap, expiry); `TelemetrySender` (behind a `protocol TelemetryTransport` so tests can inject one); `final class Telemetry: ObservableObject` tying these together with a scheduler. |
| `Sources/MouseHerdr/TelemetryViews.swift` *(new)* | The Privacy card, the "What's sent" sheet and the consent popover content. |
| `Sources/MouseHerdr/UpdateViews.swift` | Add the Privacy card to `SettingsPage`, and the extra line in `UpdateHelpPanel`. |
| `Sources/MouseHerdr/AppState.swift` | `let telemetry = Telemetry()`. Counts in `perform(_:)`, `toggleWheel`/`openRing` (with the trigger), `togglePin`, `answer`, `swipe`/`gestureUp`, `thumbWheel`, `dragger.end`, `choose(_:)` and `beginRecording`. A `telemetrySnapshot()` for the setup section. |
| `Sources/MouseHerdr/Agents.swift` | Count wheel picks (centre/wedge), closes (Escape/right click/trigger), typed answers and opening from the Agents page. Only the event is counted, never the agent. |
| `WindowDragger` (in `AppState.swift`) | `end(snap:)` reports which snap happened (half/full/quarter) to the counter. |
| `Sources/MouseHerdr/App.swift` | Start telemetry after `state.updates.start()`, only on the normal startup path. Show the consent popover beside `explainMenuBar()`. Add `--telemetry-preview`. Flush on quit. |
| `build.sh` | Nothing is needed. Optionally add a `MouseHerdrTelemetry` Info.plist key so that a fork can switch it off when building. |
| `docs/telemetry.md` *(new)*, `README.md`, `SECURITY.md` | The field list. A "Usage statistics" paragraph. Replace "does not include telemetry" with an accurate sentence and a link. |
| `Resources/ReleaseNotes.md` | A What's New entry for the release that adds it. |

Notes:
- The client needs no new dependencies (Foundation `URLSession` and `JSONEncoder`).
- All the counting methods are `@MainActor`. Sending runs on a private serial queue.

## 11. Testing plan

- **Unit tests** in `Tests/MouseHerdrTests/TelemetryTests.swift`, using a `UserDefaults` suite
  per test as `UpdateTests` does, and a fake transport:
  - It is off by default, and nothing is sent or counted while it is off.
  - Turning it off deletes the id, the counters and the queue. Turning it on makes a new UUID.
  - The environment and managed kill switches win over the toggle.
  - Report contents: a profile with a personal device name produces only the catalog id. An
    `app` or `shortcut` action produces only its kind. Snapshot test: no string in an
    encoded report is outside the allowed value sets (checked by walking the JSON).
  - Day rollover, the queue cap and expiry, retry and backoff for each status code, and
    idempotent resends.
  - Each report is 4 KB or less with every counter at its maximum.
  - `docs/telemetry.md` mentions every `TelemetryCounter` case and every field name.
- **`scripts/test_setup.py`:** `--telemetry-preview` runs with an empty home folder, prints
  valid JSON, sends nothing and exits 0. Every other developer flag makes no telemetry
  request. To check that, point `MOUSEHERDR_TELEMETRY_URL` at a local listener and assert it
  received nothing.
- **Snapshot:** add `--tab settings` with the Privacy card, in light and dark, to the review
  screenshots.
- **Manual:** watch with Little Snitch or `nettop` that there are no connections while it is
  off, and one small POST a day while it is on. Pull the network, check that the queue fills
  and later drains, and that the app stays responsive with the endpoint unreachable or
  blackholed.

## 12. Rollout

1. **Design review** of this document, and the owner's answers to §13.
2. **Server first:** deploy ingest and storage, check that IPs are not logged, and send test
   reports with `curl` using placeholder data only.
3. **Client behind a build flag:** merge with sending compiled in but the Settings card
   hidden. Test with `MOUSEHERDR_TELEMETRY_URL` against a local or staging ingest.
4. **Release N:** ship the Settings card, the consent popover, `docs/telemetry.md` and the
   updated `SECURITY.md`. Announce it in What's New and in the release notes.
5. **After 2 to 4 weeks:** check the opt-in rate, the data quality and the payload sizes,
   then prune counters nobody looks at. A counter that answers no question should go.

## 13. Open questions

1. **Opt-in versus opt-out.** This document recommends opt-in (§5). Is the lower volume of
   data acceptable?
2. **Region.** Send a coarse region (continent, or the region from the macOS locale), or
   only the language? The current proposal is language only. A region adds a little
   fingerprinting surface and answers no question we have yet.
3. **ID rotation.** Keep a stable id until the user resets it, or rotate it yearly? Yearly
   rotation would cap linkability at the cost of a spike in "new installs" once a year.
4. **Deletion requests.** Should turning telemetry off also send one last `DELETE` for the
   old id? That contradicts "nothing is sent when off", but gives a real right to erasure.
   With 90-day raw retention, is not sending it enough?
5. **Source builds.** Should source builds be able to opt in (with `build: "source"`), or
   never send at all?
6. **Unknown mice.** Would a count of unknown vendor ids (no product ids) be worth sending,
   to decide which mice to add to the catalog? Or should that stay with GitHub issues?
7. **Server hosting** and who can read the raw table. Should the dashboard be public?
8. **Retention:** is 90 days of raw data right, or would 35 days do? MAU needs only 28 days
   of raw rows plus the aggregates.
