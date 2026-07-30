# FocusSession v1 Product Specification

Status: implementation baseline  
Working name: FocusSession  
Target: macOS 26 on Apple silicon

## Product intent

FocusSession is a private, local-first menu-bar app for deliberate work sessions. One action starts a time-bounded session. During the session, selected distracting websites and native apps are unavailable except during short, earned breaks.

The product is designed to interrupt impulsive switching, not to act as parental-control or anti-tamper software. It always has a clear recovery path and never installs an indefinite system-level lock.

## Product principles

- Local-only by default and by design: no account, backend, cloud sync, analytics, advertising, or subscription.
- Low interruption: one primary start action, event-driven enforcement, and restrained notifications.
- Strong everyday friction with safe recovery: restricted content is redirected or hidden, but a session can be ended deliberately and all enforcement carries an absolute expiry.
- Transparent permissions: each capability is explained and requested separately when first used.
- Content minimization: never collect page titles, full URLs, messages, page contents, screenshots, or keystrokes.
- Neutral language: blocked screens explain state and timing without shame, scores, quotes, or moralizing.

## v1 scope

### Platforms and surfaces

- Native menu-bar app for macOS 26 on Apple silicon.
- The menu-bar label uses a monochrome hourglass. Inactive, its sand rests
  mostly in the bottom. Starting a session gives it one restrained flip, then
  sand moves from top to bottom to show approximate overall session progress.
- A single Chromium Manifest V3 extension build supported in:
  - Google Chrome
  - Brave
- A local native-messaging bridge between each installed extension and the menu-bar app.
- Local statistics and a compact statistics/settings window.
- Optional user-configured macOS Shortcuts for Work Focus integration.

### Default restricted services

The initial blocklist is enabled by default and remains editable:

| Service | Browser | Native app |
|---|---:|---:|
| Facebook | Yes | Yes |
| Messenger | Yes | Yes |
| Instagram | Yes | Yes |
| WhatsApp | Yes | Yes |

Subdomains are normalized to their service. Native-app matching uses bundle
identifiers rather than display names. The settings interface accepts a pasted
domain or full URL, and lets the user add an installed app with a native file
picker; advanced users can also enter a bundle identifier directly.

Restrictions and cycle timing belong to a named local profile. The initial
profile is `Deep Work`; users can rename it, duplicate its behavior into new
profiles, delete extra profiles, and edit each profile's domains, native bundle
identifiers, focus duration, and break duration.

## Session model

### Starting

- The idle menu presents one configurable session length rather than duration
  presets or an absolute custom end.
- Before starting, the user can configure the focus interval (how often a break
  is earned), break length, or choose no breaks.
- Starting shows a cancellable three-second countdown. The absolute
  `scheduledEndAt` is calculated when that countdown completes.
- v1 ships with the `55/5` break pattern:
  - 55 minutes restricted
  - one manually claimed five-minute free-use break
- In no-break mode, restrictions remain active for the entire session and no
  break becomes available.

### Absolute-time semantics

Every session persists an absolute `startedAt` and `scheduledEndAt`.

- A session scheduled from 14:00 to 18:00 ends at 18:00.
- Sleep, screen lock, app termination, browser termination, and Mac restart do not pause or extend it.
- On launch or wake, components recompute state from persisted timestamps.
- If 55 wall-clock minutes elapse while the Mac sleeps, one break is available on wake.
- If a break expires while the Mac sleeps, restrictions are active on wake.
- If the scheduled end passes while the Mac sleeps or is shut down, the session is complete on the next launch.
- No pause operation exists in v1.

Changing the system clock is outside the anti-bypass guarantees of v1. State still contains both start and scheduled-end timestamps so corrupted or implausible state can never create an unbounded lock.

### Focus and break state

An active session has exactly one of these phases:

1. `focusing`: restricted services are blocked. The current 55-minute interval advances by wall clock.
2. `breakAvailable`: one break has been earned but not claimed. Restrictions remain active.
3. `onBreak`: all configured restricted services are available until `breakEndsAt`.

Rules:

- When breaks are enabled, a break is earned after the configured focus
  interval (55 minutes by default).
- The user must claim the break; it never starts automatically.
- Only one break may be pending.
- Breaks do not accumulate.
- While a break remains unclaimed, no second focus interval progresses.
- Claiming a break starts it immediately.
- A bundled browser block page automatically returns to the normalized service
  homepage after the break starts; FocusSession never stores or carries the
  attempted page path or query.
- When a break expires, the next configured focus interval starts.
- When breaks are disabled, the session remains in `focusing` until its
  scheduled end and break controls are unavailable.
- A break is shortened when necessary by the session's scheduled end.
- The scheduled end always wins: a break or extension never lengthens the overall session.

### Shot-clock break ending

- A one-minute warning is shown near the end of an active break.
- When ten seconds or less remain, a prominent `+30 seconds` control appears:
  - in the menu-bar surface;
  - in the browser overlay when a restricted website is foregrounded; and
  - in a floating native panel when a configured restricted native app is foregrounded.
- One press extends `breakEndsAt` by 30 seconds, capped by the session's scheduled end.
- The control becomes unavailable after a successful press and appears again when the updated timer reaches ten seconds.
- Extensions may be repeated without a numerical limit.
- Concurrent or duplicate presses are resolved atomically; one request cannot extend twice.
- Each successful extension and its actual added seconds are recorded when statistics are enabled.
- At zero, restricted websites return to the local blocked screen and
  restricted native apps are hidden without being quit. If a native app does
  not accept the hide request immediately, an opaque local focus shield covers
  its content until the user switches away.

### Ending early and recovery

- `End Session Early` appears in a secondary menu.
- One confirmation ends the session immediately.
- There is no phrase, delay, password, required explanation, or pause in v1.
- An early ending is recorded when statistics are enabled.
- Every enforcement copy includes `scheduledEndAt` and must stop enforcing after it, even if the native app is unavailable.
- Browser extensions retain the latest active-session snapshot locally so quitting or restarting a browser does not clear an active session.
- Each running browser extension keeps a local native-messaging state port open so native changes normally reach every browser within one second; a one-minute request remains as fallback.
- The menu-bar app persists active state atomically and resumes it after restart when the scheduled end is still in the future.
- Launch at login is offered so native-app enforcement resumes after a Mac restart.
- The repository's development uninstaller unregisters `SMAppService.mainApp`
  through the still-installed app before removing the app or native-messaging
  files. An already-disabled login item is a successful no-op. If
  unregistration fails, uninstall stops before deletion and instructs the user
  to disable Launch at Login in FocusSession Settings before retrying.
- A successful development uninstall leaves local settings and statistics in
  `~/Library/Application Support/FocusSession/` and does not remove the
  Chrome/Brave extension. The script states this explicitly so data deletion
  remains a separate, deliberate action.
- Last-resort recovery remains available through normal macOS app termination/removal and browser extension management; v1 does not attempt to defeat the device owner.

## Enforcement behavior

### Websites

During `focusing` and `breakAvailable`, navigation to a restricted domain is replaced by a bundled, local blocked page showing:

- the scheduled session end;
- the time until a break can be earned, that a break is available, or the
  remaining session time when breaks are disabled;
- `Start 5-minute break` only when a break is available;
- `Return to previous page`; and
- `Open FocusSession`, using the registered local `focussession://open` URL scheme for early ending or native settings; and
- `Extension settings`, which opens the current browser extension's options page.

During `onBreak`, restricted sites load normally. At expiry, open restricted tabs are replaced with the local blocked page. No blocked page makes a network request.

Configured browser block entries preserve the exact normalized hostname supplied by the user. A rule blocks that hostname and its child subdomains; it is never shortened to an inferred registrable domain. This prevents an unfamiliar compound suffix from accidentally broadening a rule.

### Native apps

During `focusing` and `breakAvailable`:

- a newly activated restricted app is immediately hidden;
- already-open restricted apps are hidden when a session starts;
- apps are not force-quit, preserving drafts and process state; and
- FocusSession briefly explains why the app was hidden and when access becomes available.

During `onBreak`, restricted native apps work normally. At expiry, they are
hidden if open or activated. If hiding does not take immediately, an opaque
local focus shield prevents the restricted app's content from remaining
visible while leaving its process running. Native enforcement is based on
frontmost-app events plus a low-frequency foreground consistency check, not
screen capture or aggressive polling.

## Menu-bar experience

### Idle

- Configurable session length
- `Take breaks` control
- Configurable `Break every` and `Break length` values when breaks are enabled
- Primary `Start Session`, followed by a cancellable three-second countdown
- Settings, Statistics, and Quit

### Focusing

- Scheduled end
- Time until the next break can be earned
- Current configured blocklist summary
- Secondary `End Session Early`

### Break available

- `Start 5-minute break`
- Scheduled session end
- Secondary `End Session Early`

### Break active

- Live break countdown
- `+30 seconds` only at ten seconds or less
- Scheduled session end
- Secondary `End Session Early`

## Notifications

- Notify once when a break becomes available.
- Warn once when one minute remains in a break.
- Show the shot-clock surface at ten seconds.
- Do not notify for each blocked attempt.
- The session-complete notification is off by default and can be enabled.
- Notification permission is optional; timers and enforcement work without it.

## Work Focus integration

macOS does not provide FocusSession a dependable public API for directly owning Work Focus. v1 therefore offers an optional Shortcuts adapter:

- the user may select or create a start shortcut that enables Work Focus;
- the user may select or create an end shortcut that disables or restores Focus;
- FocusSession invokes the start shortcut when a session begins;
- it invokes the configured end shortcut only if the start invocation succeeded for that session; and
- shortcut failure never blocks session start, session completion, or early ending.

Focus state synchronization and restoration beyond this best-effort behavior are not enforcement guarantees.

## Local observation and suggestions

### Prospective observation

FocusSession keeps local aggregate observation off on a fresh install and
presents it as an independent privacy setting that the user can explicitly
enable or disable at any time. When enabled, it observes:

- frontmost native-app bundle identifiers; and
- an aggregate domain derived from the active tab's hostname in the frontmost Chrome or Brave window.

The native app and extension bundle the same versioned table of common compound suffixes for aggregation. v1 does not include a complete Public Suffix List. A known compound suffix such as `co.uk` retains one additional label; other hostnames fall back to their final two labels. This approximation can group an unfamiliar suffix incorrectly for statistics. It cannot broaden configured blocking because block entries preserve exact normalized hostnames and v1 suggestions are limited to a bundled catalog of known distraction domains.

It aggregates time locally by app/service/aggregate domain. Background apps, hidden windows, and inactive tabs do not count. Once per week, the app may suggest frequently used likely distractions. A suggestion:

- never changes the blocklist automatically;
- can be accepted, dismissed, or permanently dismissed; and
- is based on local aggregates and bundled deterministic rules, not an AI or cloud classifier.

The blocklist always remains manually editable.

The native `historyEnabled` and `usageObservationEnabled` settings are authoritative and flow to extensions in every state snapshot. On receipt:

- disabling usage observation stops the current browser activity segment and clears buffered domain-activity aggregates immediately;
- disabling session history stops and clears buffered blocked-attempt statistics immediately; and
- later re-enabling either setting cannot flush data observed while it was disabled.

Buffered records carry their observation-time `sessionID`, whether the observation occurred on a break, and whether history was enabled. Flush-time session or settings state is never substituted for that context.

### Optional browser-history onboarding

The user may separately choose `Analyse my recent browser usage`.

- The extension requests optional browser-history permission in direct response to a user action.
- It examines at most the preceding 30 days.
- Full URLs and titles are handled only transiently inside the extension.
- Only reduced aggregate-domain visit count and last-visit time are sent to the native app.
- The extension provides a visible `Remove browser history access` action after the scan; v1 retains the permission until the user chooses that action or removes it in browser settings.
- Suggestions require confirmation before any domain is blocked.

Historical visit data does not provide reliable historical dwell time and must not be presented as such.

### Screen Time feasibility spike

A separate engineering spike will verify whether macOS 26 exposes a supported public route to historical native-app Screen Time data. Shipping v1 does not depend on it.

The spike must not use:

- undocumented Screen Time databases;
- Full Disk Access workarounds;
- UI scraping or automation of System Settings; or
- private Apple frameworks.

If no supported public API exists, historical native-app import remains deferred.

## Local statistics

When statistics are enabled, retain:

- session start, scheduled end, actual end, and completion type;
- protected session time: elapsed wall-clock session time minus claimed break time;
- completed focus intervals;
- breaks claimed and actual break seconds;
- extension count and actual extension seconds;
- early endings;
- blocked-attempt count by service/aggregate domain;
- time spent by restricted service/aggregate domain during breaks; and
- prospective aggregate foreground time used for suggestions, when local learning is separately enabled.

Never retain page titles, full URLs, URL paths or queries, messages, page contents, screenshots, window contents, or keystrokes.

Controls:

- delete one session;
- clear all session history, usage rollups, and suggestion state without resetting settings;
- disable future session history;
- disable prospective local learning; and
- clear usage aggregates and suggestion state separately.

Active-session state is persisted for recovery even when history is disabled, then removed at completion.

The dashboard labels the aggregate as `Protected session time`, not `Focused time`. It is wall-clock protection time and can include Mac sleep, screen lock, or periods when the user was away; it is not a measurement of active attention, keyboard activity, or productive work.

## Permissions

Permissions are requested just in time and presented as separate capabilities:

| Capability | Purpose | Required? |
|---|---|---:|
| Chrome/Brave extension site access | Block configured restricted domains | Required for browser enforcement |
| Native messaging | Synchronize local session and settings state | Required for browser enforcement |
| Browser `history` | Optional 30-day onboarding scan | No; requested temporarily |
| Native app-control permission, if macOS requires it | Hide restricted native apps | Required only for native enforcement |
| Notifications | Break availability and warnings | No |
| Launch at login | Resume native enforcement after restart | Recommended, user-controlled |
| Shortcuts invocation | Toggle Work Focus | No |

FocusSession must not request Screen Recording, Full Disk Access, Contacts, microphone, camera, or Accessibility unless an implementation spike proves Accessibility is necessary solely for native-app hiding. If Accessibility is required, it is requested only when the user enables native-app blocking, and the rationale is shown first.

## Performance and operating constraints

- Enforcement and observation are event-driven; no screen recording, DOM-content analysis, AI model, or high-frequency process polling.
- No outbound application or extension network traffic in v1.
- Release-gate resource limits are defined in `ACCEPTANCE_CRITERIA.md`.
- Storage uses local aggregate records and should remain in the low megabytes under normal use.

## Explicitly deferred or out of scope

- Safari extension support.
- iPhone, iPad, Windows, Android, and non-Chromium browsers.
- Cloud sync, accounts, teams, remote administration, analytics, and subscriptions.
- Automatic update checks; v1 may be distributed and updated manually.
- Tamper-proof or parental-control-grade enforcement.
- Passwords, recovery codes, irreversible locks, and an impossible-to-end mode.
- Pause-and-extend behavior.
- Automatically starting breaks.
- Accumulating or banking unused breaks.
- Per-service time allowances.
- Work/urgent exemptions for Discord or WhatsApp.
- Automatic blocklist changes.
- AI-based categorization.
- Full URL, title, content, message, screenshot, or keystroke collection.
- Private/undocumented Screen Time access.
- Reliable historical browser dwell time.
- Full Public Suffix List domain reduction; v1 uses an identical bundled common compound-suffix table for aggregate statistics only.
- Direct Focus-mode ownership beyond optional Shortcuts.
- Multi-device synchronization.
- One-action native-data reset plus cache purge across every browser profile.

## Success definition

v1 succeeds when a user can configure and start a time-bounded session, choose
predictable manually claimed breaks or no breaks, deliberately extend a break
30 seconds at a time, and is reliably redirected away from configured
Chrome/Brave sites and hidden from configured native apps—all without an
account, cloud service, invasive content collection, or material idle resource
use.
