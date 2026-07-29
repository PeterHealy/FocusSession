# Focus Session for macOS

This subtree contains the local native half of Focus Session:

- `FocusSessionApp`: a SwiftUI menu-bar app for starting sessions, claiming
  breaks, extending the shot clock, changing settings, and viewing local stats.
- `FocusSessionNativeHost`: the Chrome/Brave native-messaging helper.
- `FocusSessionCore`: the shared session engine, protocol, aggregate data model,
  and JSON persistence.
- `FocusSessionCoreTests`: deterministic unit tests for timing, persistence,
  minimization, statistics, and native-message behavior.

The package targets macOS 14 or later. Its automated release-gate environment
is Apple-silicon macOS 26. It has no third-party dependencies, account,
analytics, backend, subscription, AI model, or network code.

## Open and run

For a complete app bundle plus Chrome/Brave native-host registration, prefer
the root `scripts/install-dev.sh` flow in `README.md`.

To work on the Swift package directly:

1. Open `Package.swift` in Xcode on the Mac.
2. Select the `FocusSessionApp` scheme and the local Mac destination.
3. Build and run.
4. In Settings, enable **Launch Focus Session at login**. This is required for
   native-app protection to return automatically after a Mac restart.
5. Optionally create two Apple Shortcuts that turn Work Focus on and off, enter
   their exact names in Settings, and enable the Work Focus hook.

The bundled app handles `focussession://` URLs by activating FocusSession and
opening its Settings scene. The packaging `Info.plist` must declare:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.focussession.app</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>focussession</string>
    </array>
  </dict>
</array>
```

The Swift handler deliberately ignores every other scheme.

`SMAppService.mainApp` requires a real bundled app. Launch at Login can fail
while running an unbundled Swift Package executable or an unsigned development
artifact. A distributable build should wrap/sign `FocusSessionApp` as a normal
menu-bar `.app` before this toggle is relied on.

## Session behavior

- Choose the session length before starting, then use the cancellable
  three-second countdown.
- Configure break frequency and break length for the session, or choose no
  breaks to keep restrictions active until the session ends.
- The default cycle is 55 minutes focused, then one manually claimed 5-minute
  free-use break.
- Settings includes Strict (55/5), Standard (50/10), and Deep work (90/10)
  patterns plus custom focus/break minute controls.
- Only one break can be pending. Waiting to claim it does not accumulate more
  breaks.
- A `+30 seconds` control is available only while an active break has 10
  seconds or less remaining. It becomes available again in the final 10
  seconds of every extension, with no fixed extension count.
- Extensions are clamped to the overall scheduled session end.
- Sleep and restart never move the scheduled end time.
- Ending early requires one confirmation.
- Restricted native apps are hidden, never quit. The fresh profile starts with
  Facebook, Messenger, Instagram, and WhatsApp; users can choose any installed
  app from Settings to add it without looking up a bundle identifier.

The app observes `NSWorkspace` activation, sleep, and wake events rather than
polling the process list continuously. Foreground usage accounting pauses while
the display/Mac sleeps. A restricted native app that is foreground during the
last 10 seconds of a break receives a floating shot-clock panel with the
extension button.

## Local data

State is stored at:

```text
~/Library/Application Support/FocusSession/state.json
```

The directory is set to mode `0700`; the JSON state and any corruption backup
are set to `0600`. Writes are atomic and guarded by a separate `flock` lock so
the menu app and native host cannot interleave writes. The session engine
reconciles persisted absolute timestamps on every read, making browser/app
restarts and ordinary crashes safe.

Stored browsing data is deliberately narrow:

- Base/registrable domain
- Aggregate active seconds
- Aggregate visit count
- Last-seen timestamp

It does not store page paths, query strings, titles, searches, messages, page
content, screenshots, or window titles. Native-app usage stores bundle
identifiers and aggregate time only. Corrupt state is moved to a timestamped
local backup and replaced with safe defaults.

On a fresh install, session history is on, while prospective app/domain
observation and suggestions are off until the user explicitly enables them.

## Native messaging

Build the helper in Xcode or from Terminal on the Mac:

```sh
swift build -c release --product FocusSessionNativeHost
```

Copy the resulting executable to a stable user-owned location, for example:

```text
~/Library/Application Support/FocusSession/bin/FocusSessionNativeHost
```

Copy and edit
`NativeMessagingHosts/com.focussession.nativehost.json.example`. Replace:

- `path` with the absolute executable path.
- `REPLACE_WITH_EXTENSION_ID` with the actual unpacked or published extension
  ID.

Install the edited manifest in both locations:

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.focussession.nativehost.json
~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.focussession.nativehost.json
```

The host uses standard Chromium native-messaging framing: a four-byte
little-endian payload length followed by UTF-8 JSON. Extension-to-host input is
capped at 4 MiB; host-to-extension output follows Chrome's 1 MiB limit. Stdout
contains frames only.

Supported request `type` values:

| Type | Payload |
|---|---|
| `getState` | None |
| `startBreak` | None |
| `extendBreak` | None |
| `recordBlockedAttempt` | `service`; optional `attemptCount`, `sessionID`, `wasOnBreak`, `historyEnabledAtObservation` |
| `recordDomainActivity` | `domain`; optional `activeSeconds`, `visitCount`, `sessionID`, `wasOnBreak`, `historyEnabledAtObservation` |
| `importHistorySummary` | `historySummary[]` containing `domain`, `visitCount`, optional `lastVisitAt` |

Every response includes:

- `ok`
- `state`, even when the operation failed
- `error` with a stable code and human-readable message when `ok` is false

While a `connectNative` port remains open, the helper watches the
`FocusSession` Application Support directory. An atomic `state.json` change
causes an unsolicited `{ok,state}` response after a short debounce. This lets a
dedicated push-only browser port learn about menu-bar session starts and other
native changes without waiting for a one-minute extension alarm. All stdout
frames share one lock, so a pushed state cannot interleave with a command
response.

Dates use ISO 8601. Public state includes the current phase, absolute end,
blocking flag, focus/break countdowns, `focusDurationSeconds`,
`breakDurationSeconds`, `usageObservationEnabled`, `historyEnabled`,
shot-clock eligibility, and restricted domains.

Activity/attempt requests can carry observation-time context:

- `sessionID`
- `wasOnBreak`
- `historyEnabledAtObservation`

Session counters are attributed only to that matching active or archived
session. Delayed delivery never infers attribution from the current phase.

Example request:

```json
{"type":"recordDomainActivity","domain":"www.reddit.com","activeSeconds":3}
```

The helper reduces the supplied value to `reddit.com` before persistence. The
extension should still send hostnames rather than complete URLs.

## Work Focus

Apple does not provide a suitable public macOS API for directly changing Focus
mode from this app. The optional hook runs user-created Shortcuts through:

```text
/usr/bin/shortcuts run <shortcut name>
```

The app persists whether it successfully started Work Focus. It runs the
configured ending Shortcut after normal or early completion and retains a
cleanup marker across crashes until that ending Shortcut succeeds.

## Known limitations

- This is strong friction, not tamper-proof parental-control enforcement.
  Quitting the menu app disables native-app monitoring until Launch at Login
  starts it again; disabling the browser extension disables site blocking.
- `NSRunningApplication.hide()` avoids destroying drafts, but a determined user
  can repeatedly relaunch or unhide an app.
- Native blocking only runs while the menu app is running. Install and enable
  the bundled app at login to meet restart-resume behavior.
- Screen Time history is not read through undocumented databases. Optional
  historical onboarding comes from the extension's explicit Chrome/Brave
  history permission and imports aggregate domains only.
- Safari support is intentionally deferred.
- The package requires macOS to compile and UI-test. Run `swift test` and the
  Xcode app scheme on the target Mac before distributing it.

## Unregister Launch at Login

Before deleting the installed app bundle, run:

```sh
"/path/to/FocusSession.app/Contents/MacOS/FocusSessionApp" --unregister-login-item
```

If the login item is enabled or awaiting approval, the app unregisters it.
Already-unregistered is a successful no-op. Success writes a confirmation to
stderr and exits `0`; failure writes the localized error to stderr and exits
`1`. The process terminates without opening the menu-bar interface.
