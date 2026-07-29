# FocusSession v1 Privacy Design

Status: binding privacy requirements

## Promise

FocusSession keeps settings, session state, usage aggregates, and statistics on the user's Mac. v1 has no account, backend, cloud sync, analytics, telemetry, advertising, subscription service, or application-initiated network request.

Browser requests made when the user visits an allowed page are browser activity, not FocusSession data transfer. FocusSession's own blocked pages and overlays use only bundled local assets.

## Data inventory

| Data | Stored form | Purpose | Default retention |
|---|---|---|---|
| Settings | Local versioned state file/preferences | Session and UI behavior | Until changed |
| Blocklist | Service IDs, exact normalized hostnames, verified bundle IDs | Enforcement | Until changed/reset |
| Active session | IDs, phase, absolute timestamps, and counters | Enforcement and recovery | Until session ends |
| Session history | Start/end timestamps, completion type, interval/break/extension totals | Local statistics | Until deleted |
| Blocked attempts | Aggregate count by session and service/aggregate domain | Local statistics | Until session/history deletion |
| Break usage | Aggregate seconds by restricted service/aggregate domain | Local statistics | Until session/history deletion |
| Prospective app usage | Aggregate duration by bundle ID/service | Local suggestions | Until history clear/reset |
| Prospective web usage | Aggregate duration by reduced domain/service | Local suggestions | Until history clear/reset |
| Browser-history summary | Reduced aggregate domain, 30-day visit count, last-visit time | Initial suggestions | Until history clear/reset |
| Suggestion state | Candidate ID and accepted/dismissed state | Avoid repeated prompts | Until history clear/reset |
| Extension cache | Active session deadlines/phase, interval durations, privacy flags, and blocklist | Offline enforcement and collection gating | Until end/update |
| Extension statistic buffers | Aggregate domain/count/seconds plus observation-time session/phase/history context | Reliable delayed local submission | Until flush or related setting is disabled |
| Shortcut configuration | User-selected shortcut identifiers and per-session success flag | Optional Work Focus control | Until changed; flag until session end |

## Data never collected

FocusSession must not collect, store, log, or transmit:

- full URLs;
- URL paths, query strings, or fragments;
- page or window titles;
- browser searches;
- page text, DOM content, form values, or clipboard contents;
- Discord, WhatsApp, or other messages;
- screenshots, screen recordings, window images, camera, or microphone data;
- keystrokes or mouse input;
- contacts or address books;
- document contents or file names;
- precise content viewed within an aggregate domain;
- historical native-app Screen Time through private/undocumented access; or
- identifiers for advertising, telemetry, or cross-device tracking.

## Hostname minimization and suffix limitation

The extension may see a URL because the browser exposes it for active-tab enforcement or optional history scanning. It must immediately:

1. reject non-web schemes unless handling a bundled extension page;
2. extract the hostname;
3. canonicalize case and internationalized-domain representation;
4. derive an aggregate domain with the identical native/browser bundled common compound-suffix table;
5. map it to a configured service when applicable; and
6. discard the original URL before IPC, persistence, or logging.

For example, a URL containing a Reddit post path and query becomes only `reddit.com` and the service `reddit`.

v1 does not ship a complete Public Suffix List. For aggregate statistics and suggestions, a known compound suffix retains one additional label; an unknown suffix falls back to the final two labels and may therefore group sites imperfectly. Native and extension copies of the common table must be identical.

Configured blocking is safer and separate: each entry preserves the exact normalized hostname. It matches only that hostname and its child subdomains and is never reduced through the suffix table. Suggestions are limited to a bundled catalog of known distraction domains, so an unknown fallback aggregate is not proposed as a rule. An unknown suffix therefore cannot make blocking broader than a hostname the user deliberately configured.

## Foreground observation

Prospective learning is off on a fresh install and is separately controllable.
Enabling it is an explicit local opt-in.

- Native observation uses macOS foreground bundle-ID events.
- Browser observation uses the reduced aggregate domain of the active tab in the frontmost Chrome or Brave window.
- Background processes, inactive tabs, hidden windows, and notifications are not counted.
- Raw activation transitions are held only long enough to close the current aggregate interval.
- Persistent records are aggregate durations, not a chronological browsing trail.
- App and browser observation can be disabled without disabling manual blocking.

## Optional browser-history scan

The scan is off by default and initiated by an explicit user action.

- Scope: at most the previous 30 days.
- Browser permission: optional `history`, requested at the moment of the action.
- Processing location: within the local extension.
- Native transfer: reduced aggregate domain, visit count, and last-visit time only.
- Permission lifecycle: v1 provides a visible removal action and never reads history except during a user-initiated scan; automatic post-scan removal is deferred.
- Result meaning: frequency and recency, never claimed dwell time.
- Effect: suggestions only; nothing is added to the blocklist without confirmation.

FocusSession never stores results in `chrome.storage.sync` or initiates browser synchronization. The browser's locally visible history may itself contain visits synchronized by Chrome/Brave if the user enabled browser sync.

## Statistics choices

Session history and prospective learning are separate toggles.

- If session history is disabled, the minimum active snapshot is still stored so the current restriction has a safe expiry and can recover after restart. It is deleted when the session ends.
- If prospective learning is disabled, no new app/domain usage aggregate or suggestion state is stored.
- Turning either toggle off stops new collection immediately but does not silently delete existing history; the UI offers explicit deletion.

Every native public state sends authoritative `historyEnabled` and `usageObservationEnabled` values to extensions. When history is disabled, the extension immediately clears buffered blocked attempts. When usage observation is disabled, it closes/removes its current activity segment and immediately clears buffered domain activity. Re-enabling a setting cannot resurrect either buffer.

The extension may offer a local switch that disables browser observation more
strictly; it cannot override a native `false` setting.

Before delayed submission, each buffered record carries only the contextual `sessionID`, `wasOnBreak`, and `historyEnabledAtObservation` captured when observed. These prevent a later session, phase, or privacy-setting change from altering attribution. They do not reveal page content.

The dashboard's `Protected session time` is derived from wall-clock session
elapsed time minus claimed break time. It may include sleep, lock, or away time
and must not be presented as measured attention, active computer use, or
productive output.

User controls:

- delete one session and its dependent service aggregates;
- clear all session history, usage rollups, imported history aggregates, and suggestion state while keeping settings and blocklist;
- clear app/domain rollups and suggestion state separately;
- disable future session statistics;
- disable local learning;
- edit or restore settings separately.

A one-action reset that also purges every browser profile's extension cache is deferred. Cached enforcement still carries the absolute scheduled end and refreshes from native state.

## Local storage

Native data is stored in the app's local Application Support container, for example:

`~/Library/Application Support/FocusSession/`

Extension state uses `chrome.storage.local`. `chrome.storage.sync` is prohibited.

The app does not intentionally place data in iCloud Drive or CloudKit. Local files should be marked to avoid cloud/document synchronization. The user's own device backup or Time Machine policy is outside FocusSession's control and should be disclosed in the privacy screen.

No encryption key is uploaded or managed by FocusSession. The app relies on macOS account access controls and FileVault for data at rest. Adding application-level state-file encryption is deferred unless a clear threat model and recoverable key design are approved.

The repository's development uninstaller removes the app and native-messaging
integration only after its bundled command has successfully unregistered Launch
at Login. It deliberately retains local settings, statistics, and other state
in `~/Library/Application Support/FocusSession/`, and it does not uninstall
Chrome/Brave extensions or silently purge their local cache. The script
discloses the retained native-data path. Users can clear retained
history/usage with the in-app controls before uninstalling; full native-data
erasure requires rerunning the uninstaller with its explicit `--delete-data`
flag (or manually removing that directory). Browser-extension storage is
cleared separately by removing the extension from each browser profile.

## Network behavior

v1 includes no application network client and no automatic update check.

Allowed local communication:

- Chromium Native Messaging, including a persistent local state port;
- macOS notifications and system APIs; and
- supported local Shortcuts invocation.

The persistent native host watches only the FocusSession Application Support directory for filesystem change events. On a change it reads the same local state through the locked repository and pushes only `PublicSessionState`, including the exact normalized-hostname blocklist and authoritative privacy flags. It does not push statistics, usage rollups, browser-history summaries, or raw state-file bytes. The watcher performs no network operation.

The blocked page's `Open FocusSession` action invokes only `focussession://open`; it places no blocked hostname, session identifier, or other browsing data in the URL. `Extension settings` opens the browser's local extension options page.

Disallowed:

- telemetry or crash-report upload;
- remote configuration;
- remote blocklists or classifiers;
- CDN-hosted blocked-page assets;
- DNS/network-filter inspection;
- analytics SDKs; and
- third-party AI or API calls.

## Permissions and purpose limitation

| Permission/capability | Narrow use |
|---|---|
| Extension access to configured sites/tabs | Determine normalized active domain and enforce configured restrictions |
| Native Messaging | Exchange minimized state/config/commands and receive local state-change pushes |
| Optional browser history | One user-initiated, local 30-day aggregate scan |
| Notifications | Break-ready and break-ending notices |
| Login item | Resume native app enforcement after restart |
| Optional app-control/Accessibility | Hide configured restricted native apps only |
| Optional Shortcuts invocation | Run user-selected Work Focus start/end shortcuts |

Permissions are requested just in time. Declining one capability does not authorize or disable unrelated capabilities.

FocusSession never requests Full Disk Access or Screen Recording. Accessibility is permitted only if a documented macOS 26 spike shows supported app-hiding APIs are insufficient; it cannot be used to inspect UI text or input.

## Logging and diagnostics

Release logs use event codes, component versions, and coarse success/failure state only.

Logs must not include:

- domains or bundle IDs from usage;
- URLs or titles;
- active-session or history payloads;
- user-entered custom blocklist text;
- shortcut names;
- timestamps tied to a specific service; or
- native-messaging message bodies.

If persisted state cannot be decoded, it is moved to a timestamped local backup with file mode `0600`. The backup can contain the same settings and aggregate domain/bundle-ID usage as the state file, but cannot contain full URLs, titles, messages, or page content because FocusSession never persists them. The backup is never uploaded automatically.

No diagnostic leaves the Mac automatically.

## Screen Time spike

Historical native-app Screen Time import is not a v1 dependency. Research is limited to supported public macOS 26 APIs and official entitlements.

The implementation must not:

- read private Screen Time databases;
- request Full Disk Access to find them;
- automate or scrape the Screen Time UI; or
- link or reflect into private frameworks.

If no supported route exists, the feature remains deferred.

## Threat model and limits

FocusSession protects privacy against the product vendor and ordinary third parties by having no server or telemetry. It minimizes harm if local data is inspected by storing aggregates rather than content.

It does not protect local data from:

- another administrator or root user;
- malware with equivalent privileges;
- forensic access to an unlocked account; or
- device backups controlled by the user.

It is also not anti-tamper security. The device owner can end a session, stop the app, disable an extension, use another browser, or change the clock. Those are product-scope limits, not hidden privacy behaviors.

## Privacy verification

Before release:

- inspect manifests and entitlements for only approved permissions;
- run network capture through onboarding, a session, history scan, statistics, and deletion;
- seed distinctive full URLs/titles and verify they appear in neither IPC, logs, nor storage;
- verify `chrome.storage.sync` is unused;
- verify both deletion controls and absolute extension-cache expiry with storage inspection; and
- repeat checks in both Chrome and Brave.

Exact pass/fail tests are defined in `ACCEPTANCE_CRITERIA.md`.
