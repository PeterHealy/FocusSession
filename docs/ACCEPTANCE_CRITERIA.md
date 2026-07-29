# FocusSession v1 Acceptance Criteria

Status: release-gate specification  
Related documents: `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `PRIVACY.md`, `NATIVE_PROTOCOL.md`

Unless a criterion names a manual test, it must be covered by an automated unit, integration, or UI test. Release testing uses a release build on Apple-silicon macOS 26 with current stable Chrome and Brave.

## A. Session creation and absolute time

**AC-A01 — Configurable start**  
Given no active session, the menu exposes one editable session length, a
`Take breaks` control, and editable break frequency and length when breaks are
enabled. It does not expose duration presets or an absolute custom-end picker.

**AC-A02 — Start countdown**  
Selecting `Start Session` shows a cancellable `3`, `2`, `1` countdown. If not
cancelled, exactly one active session is created with
`scheduledEndAt = countdownCompletion + selectedDuration`, within one second.

**AC-A03 — Start timing choices**  
The session duration and focus interval are positive. Break duration is either
positive or exactly zero. The chosen focus and break timing is persisted to the
active profile only when the countdown completes; cancelling leaves it
unchanged.

**AC-A04 — Single session**  
While a session is active, no action can create a second active session. All surfaces show the same session identifier and scheduled end.

**AC-A05 — Sleep does not extend**  
Given a 14:00–18:00 session, after the Mac sleeps for any interval, `scheduledEndAt` remains 18:00.

**AC-A06 — Restart resumes**  
Given a session whose scheduled end is in the future, restarting the Mac and launching FocusSession restores the same session identifier, scheduled end, phase, and accumulated statistics.

**AC-A07 — Expiry while unavailable**  
Given a session scheduled to end while the app, browser, or Mac is unavailable, the first subsequent state evaluation reports no active session and no component enforces past `scheduledEndAt`.

**AC-A08 — No pause**  
No v1 menu, settings screen, blocked page, protocol method, or keyboard action offers session pause or pause-and-extend.

## B. Focus and break state machine

Tests in this section use an injectable clock.

**AC-B01 — Initial phase**  
A break-enabled session begins in `focusing` with restrictions active and a
break-availability time equal to the configured focus interval after
`startedAt`, unless the session ends sooner.

**AC-B02 — Manual break availability**  
At one configured focus interval of elapsed wall-clock time, the phase becomes
`breakAvailable`; restrictions remain active and a break does not start
automatically.

**AC-B03 — Claim break**  
While `breakAvailable`, one `startBreak` action starts `onBreak` immediately
with `breakEndsAt = min(now + configuredBreakDuration, scheduledEndAt)`.

**AC-B04 — No early claim**  
A `startBreak` action in any phase other than `breakAvailable` is rejected without changing state.

**AC-B05 — Nonaccumulation**  
After any amount of time in `breakAvailable`, exactly one break remains available. No additional break count or focus progress accrues.

**AC-B06 — Next interval**  
When a break expires before the session end, the phase becomes `focusing`,
restrictions resume, and the next break-availability time is exactly one
configured focus interval after that break expiry.

**AC-B07 — Sleep crossing focus threshold**  
If the clock advances through a focus threshold while the Mac is asleep, the next state evaluation yields one `breakAvailable`, never two or more.

**AC-B08 — Sleep crossing break expiry**  
If the clock advances past `breakEndsAt` but not past `scheduledEndAt` while asleep, the next state evaluation yields `focusing` with restrictions active.

**AC-B09 — Scheduled end wins**  
At `now >= scheduledEndAt`, the active session ends regardless of phase, break time, or extension state.

**AC-B10 — Public durations**  
Every native public-state response, including `inactive`, contains positive
`focusDurationSeconds` and nonnegative `breakDurationSeconds` equal to the
current normalized settings. Zero break duration means no breaks.

**AC-B11 — No-break session**  
With break duration zero, the session remains in `focusing`, restrictions stay
active through the absolute end, no break or extension action is available,
and elapsed complete focus intervals continue to be counted.

## C. Shot-clock extensions

**AC-C01 — Visibility threshold**  
The `+30 seconds` control is absent when break time remaining is greater than ten seconds and visible when remaining time is in `(0, 10]` seconds.

**AC-C02 — Valid extension**  
One valid press changes `breakEndsAt` to `min(previous breakEndsAt + 30 seconds, scheduledEndAt)`.

**AC-C03 — Re-arm**  
After a valid extension, the control is unavailable until the updated remaining time again reaches ten seconds or less.

**AC-C04 — Repeatability**  
At least ten successive valid extensions in one break pass without a fixed-limit error, demonstrating that v1 applies no numerical extension cap.

**AC-C05 — Invalid phase**  
An extension request outside `onBreak`, at zero remaining, or with more than ten seconds remaining is rejected without changing `breakEndsAt`.

**AC-C06 — Rapid duplicate and concurrent presses**  
The extension serializes state-changing requests. For two rapid or concurrent extension presses in one eligibility window, at most one succeeds: after the first commit moves the deadline outside the ten-second window, the next native evaluation is rejected. v1 has no request-ID replay protection; adding it is deferred.

**AC-C07 — Session-end clamp**  
An extension close to `scheduledEndAt` never changes `scheduledEndAt` and never produces `breakEndsAt > scheduledEndAt`.

**AC-C08 — Statistics**  
Each successful extension increments extension count once and records the actual seconds added after the session-end clamp. Failed and duplicate requests do not increment statistics.

**AC-C09 — Surfaces**  
During the final ten seconds, the control appears in the menu bar, in a content-script overlay when a restricted website is foregrounded, and in a floating native panel when a restricted native app is foregrounded. A successful extension reaches all normally connected surfaces within one second.

## D. Browser enforcement

Run every applicable criterion independently in Chrome and Brave.

**AC-D01 — Default domains**  
With the default Deep Work profile, the browser blocklist contains exactly
`facebook.com`, `instagram.com`, `messenger.com`, and `whatsapp.com`. Each
domain and its subdomains are recognized as the corresponding service.

**AC-D01a — Exact configured hostname**  
Saving `a.b.unknownsuffix` as a block entry preserves exactly that normalized hostname. It blocks `a.b.unknownsuffix` and its child subdomains, but does not block `b.unknownsuffix` or another sibling. Aggregate-domain fallback must never rewrite or broaden a configured block entry, and an arbitrary unknown fallback aggregate is not offered as a blocklist suggestion.

**AC-D01b — Identical compound-suffix table**  
Native and extension fixtures contain the same versioned common compound-suffix table and produce identical aggregate domains for every table entry and fallback case. v1 tests and UI do not claim complete Public Suffix List coverage.

**AC-D02 — Focus redirect**  
During `focusing`, attempting to load any configured restricted domain results
in a bundled local blocked page before restricted page content becomes usable.
The page names the service that was actually requested. Brave and Chrome must
not leave the previous document visible with only the address bar changed, nor
present a connection-error or indefinitely loading state.

**AC-D03 — Available-break redirect**  
During `breakAvailable`, restricted domains remain blocked, and the blocked
page offers `Start <configured duration> break`.

**AC-D03a — Claimed-break release**  
When a break starts while a bundled blocked page is visible, the page releases
automatically to the normalized service homepage after browser rules are
removed. The original path, query, fragment, and page content are not retained.

**AC-D04 — Break access**  
During `onBreak` and before `breakEndsAt`, restricted domains load normally.

**AC-D05 — Expiry of open tab**  
Within one second after break expiry, every open restricted tab known to the extension is replaced by the local blocked page.

**AC-D06 — Blocked-page contents**  
The blocked page shows the scheduled session end, correct break
status/countdown or session-remaining time in no-break mode,
`Return to previous page`, `Open FocusSession`, and `Extension settings`.
`Open FocusSession` invokes exactly `focussession://open` with no site, session,
or user data in the URL. `Extension settings` calls the extension options-page
API. The page contains no shame-based message, quote, advertisement, or remote
resource.

**AC-D07 — Cached enforcement**  
After receiving an active snapshot, quit the native app and restart the browser. The extension continues enforcing restricted domains from its local cache until the earlier of reconnection, early-end state receipt, or `scheduledEndAt`.

**AC-D08 — Absolute expiry offline**  
With the native app disconnected, the extension ceases enforcement no later than one second after cached `scheduledEndAt`.

**AC-D09 — Background exclusion**  
A restricted domain in an inactive tab or non-frontmost browser window does not accrue restricted-service break time. Only the active tab in the frontmost supported-browser window can accrue it.

**AC-D10 — Manual editing**  
Adding a domain or pasted web URL through the native settings interface,
or removing an existing row, updates the saved profile and reaches each
running extension with a healthy push port within one second after settings
are saved. With the push port deliberately disconnected, the one-minute
request fallback converges no later than 60 seconds. No suggestion changes
the list before confirmation.

**AC-D11 — Event-driven native push**  
With a persistent `connectNative` port open, changing shared native state from another process produces an unsolicited `{ok,state}` snapshot and applies its enforcement decision in the extension within one second, without waiting for the one-minute fallback.

**AC-D12 — Push reconnect and fallback**  
When the persistent native port disconnects, the extension retains safely expiring cached enforcement, schedules bounded reconnect attempts, and continues a one-minute state-request fallback. Restoring the native host re-establishes the port without restarting the browser.

## E. Native-app enforcement

**AC-E01 — Default apps**  
The default native blocklist contains the Facebook, Messenger, Instagram, and
WhatsApp bundle identifiers and no unrelated service. The settings interface
can add an installed app through a file picker without requiring the user to
find its bundle identifier.

**AC-E02 — Session start**  
Starting a session hides already-open restricted native apps without
terminating their processes. If an app rejects or delays the hide request, an
opaque local focus shield covers its content.

**AC-E03 — Activation during restriction**  
During `focusing` or `breakAvailable`, activating a restricted native app hides
it within one second and briefly displays the reason and access timing. If it
cannot be hidden immediately, the same reason and timing appear on an opaque
shield that remains until the user switches away.

**AC-E04 — Preserve process state**  
After enforcement hides or shields a restricted app, its process remains
running. Returning during a break restores the app without FocusSession having
issued quit or kill.

**AC-E05 — Break access and expiry**  
During `onBreak`, restricted native apps can remain frontmost. At break expiry they are hidden within one second and the next focus interval starts.

**AC-E06 — Foreground-only observation**  
Native usage time accrues only for the bundle identifier macOS reports as frontmost. Running, hidden, or background apps accrue no time.

**AC-E07 — Permission failure**  
If native-app enforcement lacks a required permission, browser enforcement and session timing continue; the app clearly marks native enforcement unavailable and links to the relevant System Settings pane.

## F. Early end, crash recovery, and login

**AC-F01 — Easy early end**  
`End Session Early` is in a secondary menu. One native confirmation ends the
active session immediately after the dialog closes; no delay, phrase, password,
reason, or second confirmation is required.

**AC-F02 — Propagation**  
After early ending, native enforcement stops and each running browser extension with a healthy push port applies inactive state within one second. With push deliberately unavailable, cached enforcement persists no later than the one-minute fallback refresh or the original absolute scheduled end.

**AC-F03 — Early-end record**  
With statistics enabled, actual end and completion type `ended_early` are stored exactly once.

**AC-F04 — Atomic persistence**  
Terminating the app at each persistence boundary in an automated fault-injection test yields either the preceding valid snapshot or the new valid snapshot on restart, never malformed or unbounded enforcement state.

**AC-F05 — Corrupt-state recovery**  
If persisted state cannot be decoded, FocusSession moves it to a timestamped local backup with file mode `0600`, starts from valid default state, and never exports the backup. The backup may contain the same aggregate domain/bundle-ID statistics as the state file, but cannot contain full URLs, titles, messages, or page content because those values are never persisted.

**AC-F06 — Login item**  
When launch at login is enabled, a Mac restart launches the native component and restores native enforcement for a still-active session. Disabling launch at login removes that behavior without affecting browser cache.

**AC-F07 — Development uninstall cleanup**  
Given an installed app, `scripts/uninstall-dev.sh` without `--delete-data`
invokes its bundled
executable with `--unregister-login-item` before killing the app or deleting
the app, native-host executable, or Chrome/Brave native-host manifests. The
command unregisters `SMAppService.mainApp` when its status is `enabled` or
`requiresApproval`; an already-unregistered state exits successfully without
mutation. If unregistration fails, the command exits nonzero and the script
deletes none of those targets, explains that Launch at Login must be turned off
in FocusSession Settings, and asks the user to rerun it. On success, the script
removes those targets but leaves local settings/statistics in
`~/Library/Application Support/FocusSession/` and leaves browser extensions
installed. A macOS 26 manual test confirms the login item is absent after the
successful path and that retained local data remains.

With the explicit `--delete-data` option, the same safety ordering applies and
the script also removes the native Application Support directory after the
successful unregister/removal path. It still leaves browser extensions
installed and tells the user that removing each extension clears its
per-profile cache.

## G. Work Focus and notifications

**AC-G01 — Optional Shortcuts**  
A session can start, run, and end with no Work Focus shortcuts configured.

**AC-G02 — Start invocation**  
When configured and enabled, the start shortcut is invoked once per session. Success is recorded only in active session state.

**AC-G03 — End invocation guard**  
The end shortcut is invoked once on normal or early completion only if the start shortcut succeeded for that session.

**AC-G04 — Failure isolation**  
Missing, renamed, denied, failed, or timed-out shortcuts show a non-blocking local error and do not alter session timing or enforcement.

**AC-G05 — Notifications**  
With notification permission, exactly one break-available notification and one one-minute break warning are produced per applicable cycle. Blocked attempts produce none. Session-complete notification is off in default settings.

**AC-G06 — Permission denial**  
Denying notification permission changes no timer, enforcement, shot-clock, or statistics behavior.

## H. Statistics and local learning

**AC-H01 — Allowed session fields**  
Stored session statistics contain only the fields allowed by `PRIVACY.md`. Schema and fixture inspection find no column or JSON key for title, full URL, URL path/query, content, message, screenshot, or keystroke.

**AC-H02 — Session deletion**  
Deleting one session removes that session and its dependent aggregates without changing other sessions, settings, or blocklist.

**AC-H03 — Clear history**  
`Clear all history and usage` removes completed/early-ended session records, prospective usage, imported browser-history aggregates, and suggestion review/dismissal state while retaining settings and blocklist. `Clear app and domain rollups` removes only prospective/imported usage and suggestion state, retaining session records.

**AC-H04 — History disabled**  
With session history disabled, a session persists only the minimum recovery state while active. The authoritative `historyEnabled = false` reaches healthy extension push ports within one second, clears buffered blocked-attempt aggregates immediately, and prevents new attempt buffering. Within one second of completion, no session statistics remain.

**AC-H05 — Local learning disabled**  
With local learning disabled, authoritative `usageObservationEnabled = false` reaches healthy extension push ports within one second, closes and removes the current activity segment, clears buffered domain-activity aggregates immediately, and prevents new activity buffering or history-analysis import. No prospective app/domain aggregate or weekly suggestion is stored. Blocking and optional session statistics still work.

**AC-H05a — Fresh-install privacy defaults**  
A fresh native state has local learning and distraction suggestions disabled,
while local session history remains enabled. A fresh extension has foreground
domain observation disabled. No prospective app/domain aggregate is created
until the user explicitly enables the corresponding native and extension
controls.

**AC-H06 — Prospective domain minimization**  
For active browser observation, the native store receives only an aggregate domain, aggregate active seconds/visit count, and the contextual attribution fields allowed below. Test fixtures containing paths, queries, fragments, and titles leave none of those values in native messages, logs, or storage.

**AC-H07 — Suggestions require confirmation**  
A generated suggestion does not affect blocking until the user explicitly accepts it. Permanent dismissal prevents the same normalized app/domain from being suggested again unless the user clears suggestion history.

**AC-H08 — Weekly cadence**  
The suggestions UI is surfaced at most once in any rolling seven-day period, while remaining manually accessible.

**AC-H09 — Observation-time attribution**  
Every buffered blocked-attempt or domain-activity aggregate retains the observation-time `sessionID`, `wasOnBreak`, and `historyEnabledAtObservation`. Flush tests that end one session, start another, or toggle history before reconnect prove that data is never attributed using the later session, phase, or setting. A mismatched or expired session ID is never charged to a newer session.

**AC-H10 — Protected-time label**  
The dashboard labels its wall-clock aggregate `Protected session time`, not `Focused time`. Help text states that it is elapsed session time minus claimed break time, can include sleep/lock/away time, and does not measure active attention or productive work.

## I. Optional 30-day browser-history scan

Run independently in Chrome and Brave.

**AC-I01 — Explicit user action**  
The extension requests optional `history` permission only after the user activates `Analyse my recent browser usage`; it is not requested during installation or ordinary session start.

**AC-I02 — Date bound**  
The scan query start time is no earlier than `now - 30 days`, with a one-minute test tolerance.

**AC-I03 — Local reduction**  
Before crossing native messaging, every history item is reduced with the shared common compound-suffix table to aggregate-domain visit count and last-visit timestamp. Deliberately unique URL paths, queries, titles, and fragments do not appear in native messages, app logs, or native storage.

**AC-I04 — Permission removal**  
After permission is granted, the options page provides a visible `Remove browser history access` action that calls the browser permission-removal API and confirms success. A user can skip the scan or remove permission later with no loss of blocking functionality. Automatic post-scan removal is deferred.

**AC-I05 — No dwell-time claim**  
The scan UI labels results as visits/recency and does not label or infer them as historical time spent.

**AC-I06 — Confirmation**  
Every suggested domain from the scan requires individual or explicit batch confirmation before blocklist inclusion.

## J. Privacy, network, and permissions

**AC-J01 — Zero application network**  
During first launch, extension installation/onboarding, a full session, a history scan using local browser history, statistics viewing, and data deletion, packet capture shows zero outbound connections initiated by FocusSession or its extension. Browser traffic to user-requested pages is excluded; blocked pages contain no remote resources.

**AC-J02 — Local extension storage**  
Code and manifest inspection confirm use of `chrome.storage.local`, not `chrome.storage.sync`, for cached state and settings.

**AC-J03 — Prohibited permissions**  
The shipped app does not request Screen Recording, Full Disk Access, Contacts, microphone, or camera. Accessibility is absent unless a documented native-hiding spike proves it required; if present, it is requested only after the user enables native blocking.

**AC-J04 — Just-in-time permissions**  
Browser history, notifications, native app control, launch at login, and Shortcuts are presented as distinct capabilities and can each be declined without preventing unrelated capabilities.

**AC-J05 — Logging**  
Release-mode unified logs and extension console output contain no domain, full URL, page title, app usage record, message, page content, or session-history payload. Errors use non-sensitive codes and component/version metadata.

**AC-J06 — Native-message bounds**  
The native host rejects browser-to-host frames larger than 4 MiB and refuses host-to-browser payloads larger than 1 MiB. A persistent port remains correctly framed when a direct response and filesystem-triggered push are produced concurrently.

## K. Resource limits

Measurements use an Apple-silicon Mac running macOS 26, a release build, screen awake, one active session, Chrome and Brave extensions installed, and no foreground restricted-service transitions during the sample. Browser baseline memory is excluded; extension process deltas are included where measurable.

**AC-K01 — Idle CPU**  
Over a continuous 30-minute sample after a five-minute settling period, FocusSession native components average no more than 1.0% of one CPU core and no five-minute window averages more than 2.0%.

**AC-K02 — Memory**  
Combined resident memory of the menu-bar app and two persistent native-host processes remains at or below 150 MB throughout the 30-minute sample. Each browser's extension-worker memory delta remains at or below 50 MB. The open native port may intentionally keep the worker and host resident, but neither runs a busy loop.

**AC-K03 — Wakeups**  
During the same event-idle sample, native idle wakeups average no more than five per second. The persistent native host uses a filesystem dispatch source rather than directory polling; the extension keeps a one-minute request fallback. No source polls foreground applications or browser state more frequently than once per second; visible countdowns may update once per second.

**AC-K04 — Storage**  
A fixture containing 1,000 sessions, 100,000 blocked-attempt increments, 10,000 aggregate app/domain rows, and settings occupies no more than 25 MB across the native JSON state file and extension local storage, excluding application binaries and a deliberately retained corrupt-state backup.

**AC-K05 — Initial scan responsiveness**  
Scanning 100,000 local browser-history entries completes or can be cancelled without blocking browser UI for more than 100 ms in any single main-thread task. Peak additional native stored data remains within AC-K04 after aggregation.

## L. Deferred validation

These are not v1 feature-release blockers except where a prohibited fallback is discovered:

**AC-L01 — Screen Time spike**  
Document whether macOS 26 provides a supported public API that permits a native macOS app to access historical per-app Screen Time data with user authorization.

**AC-L02 — Prohibited fallback**  
Regardless of AC-L01's result, no shipped code reads undocumented Screen Time databases, requests Full Disk Access for this purpose, scrapes System Settings, or links private frameworks.

**AC-L03 — Safari**  
No Safari extension is required for v1; product UI clearly labels browser enforcement as Chrome and Brave only.

**AC-L04 — One-action full reset**  
A single command that removes native state/preferences and purges cached state in every browser profile is deferred. v1 instead provides separate controls for session-history deletion and usage-rollup/suggestion deletion; browser caches expire safely at `scheduledEndAt` or update at the next native refresh.

**AC-L06 — Automatic history-permission release**  
Automatically releasing optional browser-history permission immediately after a completed/cancelled scan is deferred. v1 exposes an explicit removal action and never reads history except during a user-initiated scan.

## Release rule

v1 may ship only when all criteria A–K pass, except a platform-specific criterion explicitly marked unavailable by a documented macOS 26 behavior and accompanied by a user-visible capability degradation that preserves timing, privacy, and safe recovery. Section L must be documented, but historical Screen Time import itself is deferred.
