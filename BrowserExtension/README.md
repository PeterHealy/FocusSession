# Focus Session browser extension

Manifest V3 companion for the local Focus Session macOS app. It supports Chrome
and Brave and talks only to the registered native messaging host
`com.focussession.nativehost`.

## What it does

- Caches the native app's absolute session end, focus/break phase, next-break
  time, break deadline, and blocklist in `chrome.storage.local`.
- Installs persistent dynamic redirect rules during focus intervals. Those rules
  continue to work while the extension service worker is asleep or the native
  app is temporarily unavailable.
- Redirects the default Facebook, Messenger, Instagram, and WhatsApp sites
  (including subdomains) to a local blocked page. Any sites the user adds in
  the macOS app are handled in the same way.
- The blocked page can open the FocusSession app through the
  `focussession://open` custom scheme or open extension settings, always from an
  explicit user click.
- Lets an earned break be claimed from the blocked page or popup.
- Shows a page overlay only during the final 10 seconds of a break. Its `+30
  sec` action is repeatable once the native app makes it available again.
- Restores redirect rules and moves open restricted tabs to the local blocked
  page when the break reaches zero.
- Stores and forwards blocked-attempt and foreground-domain totals using base
  domains only.
- Offers an explicit, optional scan of the last 30 days of browser history.
  URLs and titles are processed transiently; only base-domain visit counts and
  recency are sent to the native app.

The macOS app remains the source of truth. The extension cannot start or end a
work session. Active-domain observation is off on a fresh install and requires
both the native app's local-learning opt-in and the extension-local toggle.

## Development

Requirements: Node 20 or later for tests. The extension itself has no package
dependencies and makes no network requests.

```sh
npm test
npm run check
```

To load it unpacked:

1. Open `chrome://extensions` in Chrome or `brave://extensions` in Brave.
2. Enable **Developer mode**.
3. Choose **Load unpacked** and select this `BrowserExtension` directory.
4. Copy the extension ID shown by the browser.
5. Register the native host for that browser as described below.

Chrome and Brave generally assign separate IDs to separately loaded copies. Add
both origins to the host manifest if testing both.

## Native host registration on macOS

The native host manifest is owned by the macOS app/installer, not this
extension. During development it can be placed at:

- Chrome: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.focussession.nativehost.json`
- Brave: `~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.focussession.nativehost.json`

Example:

```json
{
  "name": "com.focussession.nativehost",
  "description": "Focus Session native messaging bridge",
  "path": "/absolute/path/to/focus-session-native-host",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://CHROME_EXTENSION_ID/",
    "chrome-extension://BRAVE_EXTENSION_ID/"
  ]
}
```

The executable at `path` must implement Chromium's length-prefixed native
messaging framing.

## Native protocol

Every request is a flat JSON object. There is intentionally no web service,
account token, analytics identifier, or cloud endpoint.

| Request | Shape |
|---|---|
| Read state | `{"type":"getState"}` |
| Claim break | `{"type":"startBreak"}` |
| Add shot-clock time | `{"type":"extendBreak"}` |
| Record blocked attempts | `{"type":"recordBlockedAttempt","service":"reddit","domain":"reddit.com","attemptCount":4,"sessionID":"UUID","wasOnBreak":false,"historyEnabledAtObservation":true}` |
| Record activity | `{"type":"recordDomainActivity","domain":"reddit.com","activeSeconds":42,"sessionID":"UUID","wasOnBreak":false,"historyEnabledAtObservation":true}` |
| Import history | `{"type":"importHistorySummary","historySummary":[{"domain":"reddit.com","visitCount":7,"lastVisitAt":"2026-07-29T14:00:00.000Z"}]}` |

Activity periods longer than 3,600 seconds are split into multiple
`recordDomainActivity` messages. Buffered blocked attempts are sent once per
session/service/domain/context aggregate with integer `attemptCount`; it
defaults to `1` and is clamped to `1...10000`. Both event types retain the
session, break phase, and native history preference captured when the event
occurred, so a delayed flush cannot rewrite their accounting context.

Successful responses use `{"ok":true}`. `getState` returns the following
`state`; `startBreak` and `extendBreak` should return it too. If a successful
mutation omits `state`, the extension immediately follows it with `getState`.

```json
{
  "ok": true,
  "state": {
    "isSessionActive": true,
    "sessionID": "UUID",
    "startedAt": "2026-07-29T14:00:00.000Z",
    "scheduledEndAt": "2026-07-29T18:00:00.000Z",
    "generatedAt": "2026-07-29T14:15:00.000Z",
    "phase": "focusing",
    "focusAvailableAt": "2026-07-29T14:55:00.000Z",
    "breakEndsAt": null,
    "canStartBreak": false,
    "canExtendBreak": false,
    "focusDurationSeconds": 3300,
    "breakDurationSeconds": 300,
    "usageObservationEnabled": true,
    "historyEnabled": true,
    "blockedDomains": [
      "facebook.com",
      "instagram.com",
      "messenger.com",
      "whatsapp.com"
    ]
  }
}
```

Supported native phases are `inactive`, `focusing`, `breakAvailable`, and
`onBreak`. Dates may be ISO-8601 strings, Unix milliseconds, or Unix seconds at
the adapter boundary; the cache always stores milliseconds.

Failures use a structured error and best-effort state:
`{"ok":false,"state":{},"error":{"code":"notReady","message":"A break is not ready yet."}}`.
The browser adapter also accepts a legacy string-valued `error`.

## Enforcement lifecycle

1. On worker/browser startup, cached state is derived against the current wall
   clock and applied before querying the native host.
2. Focus state installs main-frame dynamic redirect rules and checks already
   open restricted tabs.
3. Break state removes those rules. Restricted pages receive the cached
   absolute break deadline.
4. At ten seconds remaining, only restricted active-break pages start the
   short-lived shot-clock timer and show the extension control.
5. At zero, both a persistent browser alarm and the content script request
   re-enforcement. Rules are restored before open restricted tabs are moved to
   the local blocked page.
6. The absolute scheduled end always wins. Sleep, browser restart, and native
   host downtime do not extend a session.

The extension keeps a native messaging port open for push-only state snapshots.
It posts one `getState` request when the port connects, applies every subsequent
state snapshot immediately, and reconnects with bounded backoff if the host
exits. Native state is also checked once per active minute and whenever the
popup, blocked page, or an action requires it. The minute check is recovery for
a failed push channel, not the normal start-session path.

## Privacy and resource behavior

- No network calls, remote backend, account, analytics, screen capture, DOM
  inspection, page-content processing, or AI model.
- No title or full URL is written to storage or passed through extension
  messaging.
- Foreground tracking uses browser tab/window and idle events. Buffered entries
  contain base domain, aggregate seconds, session ID, break-state Boolean, and
  the native history preference at observation time only.
- Native `usageObservationEnabled` is a hard upper bound on prospective domain
  observation and the optional browser-history scan. Effective foreground
  observation additionally requires the extension-local opt-in. Turning the
  native permission off stops the current segment and clears buffered activity.
- The extension-local foreground-observation toggle is off on a fresh install.
- Native `historyEnabled` controls session-stat retention. Turning it off stops
  and clears blocked-attempt buffering; domain activity may continue when usage
  observation remains enabled and records
  `historyEnabledAtObservation: false`.
- The all-sites host permission is needed for custom native blocklist domains,
  active-domain aggregation, and the shot-clock overlay. The content script is
  dormant except on a configured restricted domain during an active break.
- `history` is an optional permission requested only from the analysis button.
  It can be removed on the same settings page.
- Browser-history analysis uses actual visits from the selected 30-day window,
  keeps at most 5,000 aggregate domains, and clears in-memory references after
  import.

## Known v1 limitations

- Safari is not supported yet.
- Disabling/removing the extension, editing extension storage in developer
  tools, or removing the native host remains a bypass. V1 provides deliberate
  friction, not an OS security boundary.
- Browser-internal pages such as `chrome://` and `brave://` cannot be observed
  or redirected.
- Base-domain extraction includes common compound suffixes but not the complete
  public suffix list. An uncommon country-code suffix can be grouped too
  broadly during history/activity analysis; explicit block matching still uses
  the exact configured hostname.
- Break claims and extensions require the native host. Cached state continues
  enforcement offline, but the extension does not make authoritative session
  mutations by itself.
- A browser crash can lose the final unrolled activity segment. It does not
  weaken cached blocking.
- The dynamic-rule namespace reserves 1,000 blocklist entries for v1.
