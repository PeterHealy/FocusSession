# FocusSession Native Messaging Protocol v1

Status: current implementation contract  
Native host: `com.focussession.nativehost`

## Purpose

The Chrome/Brave extension uses Chromium Native Messaging to:

- fetch the current authoritative session state;
- start an earned break;
- add a 30-second shot-clock extension;
- report aggregate blocked attempts;
- report aggregate foreground-domain activity; and
- submit an optional, locally reduced 30-day browser-history summary.

The implemented v1 protocol is deliberately small. Requests are flat JSON objects, and every request receives one response containing the current public state. A dedicated persistent port may also receive unsolicited success responses after native state changes. There is currently no protocol-version field, request ID, state revision, or native command to end a session.

## Transport and framing

- Transport: Chromium Native Messaging over standard input/output.
- Encoding: UTF-8 JSON.
- Request framing: four-byte unsigned little-endian payload length, followed by the JSON payload.
- Response framing: the same four-byte little-endian length and JSON payload.
- Maximum browser-to-host input: 4 MiB.
- Maximum host-to-browser output: 1 MiB.
- Dates: the host's custom decoder accepts ISO 8601 UTC strings with or without
  fractional seconds; responses use `JSONEncoder`'s ISO 8601 date strategy.
- UUIDs: canonical hyphenated JSON strings; observation context uses `null`
  when no session was active.
- One request produces exactly one direct response.
- A long-lived `connectNative` state port can additionally receive unsolicited `{ok,state}` snapshots.
- The host reads requests until the browser closes the native-messaging stream or a framing error occurs.
- No TCP, HTTP, WebSocket, or network listener is used.

A malformed frame or input exceeding 4 MiB returns an error response when possible, after which the host closes the stream for framing-level failures. A response exceeding 1 MiB is rejected by the response writer.

## Connection modes

### One-shot commands

The extension uses `sendNativeMessage` for ordinary reads, mutations, and aggregate submissions. The launched host reads the request, writes its direct response, and exits when the browser closes the stream.

### Persistent state port

Each running extension creates a dedicated `connectNative` port and immediately sends:

```json
{
  "type": "getState"
}
```

The host returns the direct response, then keeps the connection open. A filesystem dispatch source watches the local FocusSession Application Support directory. After a change, a 40 ms debounce coalesces related filesystem events, the host reconciles current state, and it writes an unsolicited success response with the same `{ok,state}` schema.

Each Chrome/Brave extension instance has its own persistent host process and watcher. Response writes are locked so a requested response and pushed response never interleave at the byte-frame level. The extension retains a one-minute `getState` fallback and reconnects a dropped push port with bounded exponential backoff.

## Privacy boundary

Protocol values may contain only exact normalized block hostnames, reduced aggregate domains, service labels, aggregate seconds/counts, observation-time attribution, session-control commands, and aggregate history-summary entries.

The protocol must never contain:

- a full URL;
- a URL path, query, or fragment;
- a page title;
- page or message content;
- a screenshot; or
- keystroke/input data.

Release builds must not log request or response bodies.

## Request schema

All request fields are top-level:

```json
{
  "type": "recordDomainActivity",
  "domain": "reddit.com",
  "activeSeconds": 42,
  "visitCount": 1,
  "sessionID": "6E71DBE4-F090-4818-A803-6D6CFAD38C74",
  "wasOnBreak": true,
  "historyEnabledAtObservation": true
}
```

Supported fields:

| Field | Type | Used by |
|---|---|---|
| `type` | String, required | Every request |
| `service` | String | `recordBlockedAttempt` |
| `domain` | String | `recordBlockedAttempt`, `recordDomainActivity` |
| `attemptCount` | Integer | `recordBlockedAttempt` |
| `activeSeconds` | Number | `recordDomainActivity` |
| `visitCount` | Integer | `recordDomainActivity` |
| `sessionID` | UUID or `null` | `recordBlockedAttempt`, `recordDomainActivity` |
| `wasOnBreak` | Boolean | `recordBlockedAttempt`, `recordDomainActivity` |
| `historyEnabledAtObservation` | Boolean | `recordBlockedAttempt`, `recordDomainActivity` |
| `historySummary` | Array of history entries | `importHistorySummary` |

Clients should send only fields used by the selected request type. The current Swift decoder may ignore unknown JSON keys, but callers must not rely on that behavior.

For both buffered-stat methods, `sessionID`, `wasOnBreak`, and
`historyEnabledAtObservation` are observation-time context. Extension-generated
v1 requests always include all three; `sessionID` is `null` outside a session.

### Request types

#### `getState`

Returns current public state without intentionally mutating it. State reconciliation may complete an expired session before the response is produced.

```json
{
  "type": "getState"
}
```

#### `startBreak`

Starts the single earned break.

```json
{
  "type": "startBreak"
}
```

Valid only when `state.canStartBreak` is `true`. The native session service sets:

```text
breakEndsAt = min(now + configured break duration, scheduledEndAt)
```

On success, returned state has phase `onBreak`.

#### `extendBreak`

Adds the configured 30-second shot-clock extension.

```json
{
  "type": "extendBreak"
}
```

Valid only when `state.canExtendBreak` is `true`: an active break has more than zero and no more than ten seconds remaining, and its current end precedes the session end.

The native session service sets:

```text
breakEndsAt = min(previous breakEndsAt + 30 seconds, scheduledEndAt)
```

The session's scheduled end never changes. A second immediate call normally fails because the first extension moves the break outside the ten-second eligibility window. There is no request ID or protocol-level replay cache in v1.

#### `recordBlockedAttempt`

Increments the matching observed session's aggregate blocked-attempt count for
a normalized service label. A locally buffered aggregate is submitted in one
request.

```json
{
  "type": "recordBlockedAttempt",
  "service": "reddit",
  "domain": "reddit.com",
  "attemptCount": 4,
  "sessionID": "6E71DBE4-F090-4818-A803-6D6CFAD38C74",
  "wasOnBreak": false,
  "historyEnabledAtObservation": true
}
```

`service` is required. It must be non-empty, at most 255 characters, and contain no `/`, `?`, or `#`. This method does not accept a URL or page title.

`domain` contains the exact normalized configured hostname that matched the
blocked navigation.
`attemptCount` defaults to `1` when omitted and must be an integer from `1`
through `10,000`. The browser extension clamps locally buffered aggregates to
that range before sending, allowing one native process invocation per aggregate
rather than one invocation per blocked attempt.

`sessionID`, `wasOnBreak`, and `historyEnabledAtObservation` are captured when
the attempt occurs, not when the buffer is flushed. For a blocked attempt,
`wasOnBreak` is normally `false`. The native service retains the session
statistic only for its matching session and never assigns it to whatever
session happens to be active at flush time.

If there is no matching session, history was disabled at observation, or
authoritative history collection is disabled, the service may accept the call
without retaining a statistic; enforcement state is still returned.

#### `recordDomainActivity`

Adds privacy-minimized, already-aggregated prospective browser usage.

```json
{
  "type": "recordDomainActivity",
  "domain": "reddit.com",
  "activeSeconds": 42,
  "visitCount": 1,
  "sessionID": "6E71DBE4-F090-4818-A803-6D6CFAD38C74",
  "wasOnBreak": true,
  "historyEnabledAtObservation": true
}
```

Rules:

- `domain` is required, represents a reduced aggregate domain, and is normalized again by the native service.
- `activeSeconds` defaults to `0` when omitted.
- `visitCount` defaults to `0` when omitted.
- `activeSeconds` must be between `0` and 3,600 for one call.
- `visitCount` must be non-negative.
- `sessionID` is the observed session UUID or `null`.
- `wasOnBreak` records the observed phase and controls whether activity is eligible for restricted-service break-time statistics.
- `historyEnabledAtObservation` records the authoritative history flag seen at observation.
- Full URLs and titles are invalid.
- The extension reports only activity already determined to be in the active tab of a focused browser window.

The native app controls whether usage observation is retained. Prospective
aggregate usage and session-specific break statistics are evaluated separately:
usage requires authoritative `usageObservationEnabled`, while session
attribution additionally requires matching observation context. A later
session, phase, or history toggle is never substituted.

#### `importHistorySummary`

Imports the locally reduced results of an explicit optional browser-history scan.

```json
{
  "type": "importHistorySummary",
  "historySummary": [
    {
      "domain": "reddit.com",
      "visitCount": 17,
      "lastVisitAt": "2026-07-28T20:10:00Z"
    },
    {
      "domain": "instagram.com",
      "visitCount": 8,
      "lastVisitAt": null
    }
  ]
}
```

`historySummary` is required. Each entry has:

| Field | Type | Meaning |
|---|---|---|
| `domain` | String, required | Reduced aggregate domain |
| `visitCount` | Integer, required | Non-negative visit count |
| `lastVisitAt` | ISO 8601 date or `null` | Most recent visit in the scan window |

The browser extension must enforce the 30-day scan window before reduction and submission. The native protocol intentionally receives no raw entries, scan URLs, titles, or dwell-time claims.

Reduction uses the identical bundled common compound-suffix table in native and
browser code, not a complete Public Suffix List. Configured block entries do not
pass through this reduction and preserve exact normalized hostnames. Arbitrary
fallback aggregates are not promoted to block suggestions; v1 suggestions use
a bundled known-domain catalog.

The current implementation submits the summary in one message; the extension must reject or locally reduce a result that would exceed the 4 MiB native-host input limit. Chunking is deferred.

## Response schema

Every decoded request returns:

```json
{
  "ok": true,
  "state": {
    "generatedAt": "2026-07-29T13:00:00Z",
    "phase": "breakAvailable",
    "isSessionActive": true,
    "shouldBlockRestrictedServices": true,
    "sessionID": "6E71DBE4-F090-4818-A803-6D6CFAD38C74",
    "startedAt": "2026-07-29T12:00:00Z",
    "scheduledEndAt": "2026-07-29T16:00:00Z",
    "sessionRemainingSeconds": 10800,
    "focusAvailableAt": "2026-07-29T12:55:00Z",
    "focusRemainingSeconds": 0,
    "breakEndsAt": null,
    "breakRemainingSeconds": 0,
    "canStartBreak": true,
    "canExtendBreak": false,
    "focusDurationSeconds": 3300,
    "breakDurationSeconds": 300,
    "historyEnabled": true,
    "usageObservationEnabled": true,
    "blockedDomains": [
      "facebook.com",
      "instagram.com",
      "messenger.com",
      "whatsapp.com"
    ]
  }
}
```

On failure:

```json
{
  "ok": false,
  "state": {
    "generatedAt": "2026-07-29T13:00:00Z",
    "phase": "breakAvailable",
    "isSessionActive": true,
    "shouldBlockRestrictedServices": true,
    "sessionID": "6E71DBE4-F090-4818-A803-6D6CFAD38C74",
    "startedAt": "2026-07-29T12:00:00Z",
    "scheduledEndAt": "2026-07-29T16:00:00Z",
    "sessionRemainingSeconds": 10800,
    "focusAvailableAt": "2026-07-29T12:55:00Z",
    "focusRemainingSeconds": 0,
    "breakEndsAt": null,
    "breakRemainingSeconds": 0,
    "canStartBreak": true,
    "canExtendBreak": false,
    "focusDurationSeconds": 3300,
    "breakDurationSeconds": 300,
    "historyEnabled": true,
    "usageObservationEnabled": true,
    "blockedDomains": ["reddit.com"]
  },
  "error": {
    "code": "missingField.service",
    "message": "The service field is required for this request."
  }
}
```

The response always includes a best-effort public `state`, including on method errors. `error` is absent on success.

## Public state

| Field | Type | Meaning |
|---|---|---|
| `generatedAt` | ISO 8601 date | Native time used to generate this snapshot |
| `phase` | Enum | `inactive`, `focusing`, `breakAvailable`, or `onBreak` |
| `isSessionActive` | Boolean | Whether an unexpired session exists |
| `shouldBlockRestrictedServices` | Boolean | Native authoritative restriction decision |
| `sessionID` | UUID or `null` | Current session identity |
| `startedAt` | ISO 8601 date or `null` | Absolute session start |
| `scheduledEndAt` | ISO 8601 date or `null` | Hard enforcement expiry |
| `sessionRemainingSeconds` | Number | Derived, non-negative display value |
| `focusAvailableAt` | ISO 8601 date or `null` | Deadline at which the current break becomes available |
| `focusRemainingSeconds` | Number | Derived, non-negative display value |
| `breakEndsAt` | ISO 8601 date or `null` | Active break's hard expiry |
| `breakRemainingSeconds` | Number | Derived, non-negative display value |
| `canStartBreak` | Boolean | Whether `startBreak` is currently valid |
| `canExtendBreak` | Boolean | Whether `extendBreak` is currently valid |
| `focusDurationSeconds` | Number | Current configured focus-interval duration |
| `breakDurationSeconds` | Number | Current configured nominal break duration |
| `historyEnabled` | Boolean | Authoritative native session-history setting |
| `usageObservationEnabled` | Boolean | Authoritative native app/domain observation setting |
| `blockedDomains` | Array of strings | Current exact normalized-hostname browser blocklist |

### State invariants

In every phase, `focusDurationSeconds > 0`, `breakDurationSeconds > 0`,
`historyEnabled` and `usageObservationEnabled` reflect current native settings,
and `blockedDomains` preserves the configured normalized hostnames.

#### `inactive`

- `isSessionActive = false`
- `shouldBlockRestrictedServices = false`
- session-specific IDs/timestamps are `null`
- `canStartBreak = false`
- `canExtendBreak = false`
- `blockedDomains` remains populated from settings

#### `focusing`

- `isSessionActive = true`
- `shouldBlockRestrictedServices = true`
- `scheduledEndAt` and `focusAvailableAt` are non-null
- `canStartBreak = false`
- `canExtendBreak = false`

#### `breakAvailable`

- `isSessionActive = true`
- `shouldBlockRestrictedServices = true`
- `focusRemainingSeconds = 0`
- `canStartBreak = true`
- `canExtendBreak = false`

#### `onBreak`

- `isSessionActive = true`
- `shouldBlockRestrictedServices = false`
- `breakEndsAt` is non-null and no later than `scheduledEndAt`
- `canStartBreak = false`
- `canExtendBreak = true` only in the final eligibility window

## Client enforcement rules

The extension caches the latest successful `state` in `chrome.storage.local`.

It blocks a domain when all are true:

```text
state.isSessionActive
AND local now < state.scheduledEndAt
AND state.shouldBlockRestrictedServices
AND domain matches state.blockedDomains
```

Safety rules:

- `scheduledEndAt` is the hard local expiry even if the native host is unavailable.
- A missing or invalid active-session expiry must not create enforcement.
- `blockedDomains` entries are matched as exact normalized hostnames plus child subdomains; clients must not run them through aggregate-domain reduction.
- An `onBreak` cache stops allowing restricted domains at `breakEndsAt`.
- After `breakEndsAt`, the extension resumes restriction from cached absolute values and refreshes native state when available.
- Derived remaining-second fields are display hints; clients calculate countdowns from `generatedAt` plus the absolute deadlines.
- `historyEnabled` and `usageObservationEnabled` are native-authoritative; extension-local toggles cannot override them.
- On `historyEnabled = false`, the extension immediately clears its blocked-attempt buffer and stops creating new attempt aggregates.
- On `usageObservationEnabled = false`, the extension immediately closes/removes its current activity segment, clears its domain-activity buffer, and stops creating new activity aggregates.
- The extension applies requested and pushed snapshots, refreshes after every mutating request, and retains a one-minute/lifecycle-triggered fallback while active.
- Delivery of state notifications to open tabs is best-effort and bounded. A frozen, discarded, or otherwise unresponsive tab must not delay cache or dynamic-rule updates, absolute expiry, early-end propagation, or later state snapshots.

Because v1 has no revision field, a requested response and a pushed response are not explicitly orderable. The extension serializes state-changing requests (`startBreak` and `extendBreak`) and processes native snapshots through one state queue. Each snapshot is a complete authoritative view generated after native reconciliation. Adding explicit state revisions and protocol idempotency keys is a deferred hardening item.

## Errors

Protocol framing/validation codes implemented directly by the native layer:

| Code | Meaning |
|---|---|
| `missingField.service` | `recordBlockedAttempt` omitted `service` |
| `missingField.domain` | `recordDomainActivity` omitted `domain` |
| `missingField.historySummary` | `importHistorySummary` omitted `historySummary` |
| `malformedFrame` | Native framing was incomplete or invalid |
| `messageTooLarge` | Input exceeded 4 MiB or output exceeded 1 MiB |
| `internalError` | An unexpected error occurred |

Session-service validation and phase failures use the Swift case name as their error code, including errors such as no active session, break unavailable, extension unavailable, invalid service/domain, or invalid aggregate values. Clients must display friendly local copy rather than exposing raw case names to the user.

## Compatibility and deferred hardening

The current implementation is protocol v1 by repository/package version, but it does not place a version field in messages.

Deferred:

- explicit `protocolVersion`;
- request IDs and replay/idempotency cache;
- state/config revisions;
- scan chunking;
- client identity/capability negotiation; and
- a protocol command for early end (early end remains a native-app UI action).

Any future incompatible change must introduce explicit version negotiation before changing existing field meaning.

## Protocol tests

The native and extension test suites must cover:

- every request type and its required fields;
- all four phase strings;
- `focusDurationSeconds`, `breakDurationSeconds`, `historyEnabled`, and
  `usageObservationEnabled` in every public state;
- ISO 8601 date encoding/decoding;
- 4 MiB input and 1 MiB output rejection;
- a state payload on both success and failure;
- an initial response and unsolicited changed-state response on a persistent port;
- filesystem-event coalescing without frame interleaving;
- one-second normal push convergence and one-minute fallback convergence;
- session-end and break-end clamps;
- flat request encoding with no nested `payload`;
- one `recordBlockedAttempt` request per buffered aggregate, with
  `attemptCount` defaulting to `1` and bounded to `1...10000`;
- `sessionID`, `wasOnBreak`, and `historyEnabledAtObservation` round-tripping
  on both buffered-stat request types;
- immediate related-buffer clearing when either authoritative collection flag
  changes to `false`;
- stale/mismatched session context never being attributed to a newer session;
- exact configured-hostname blocking remaining independent from common
  compound-suffix aggregate reduction;
- extension serialization of state-changing requests;
- full URL/title/path/query fixtures absent from native messages and storage; and
- offline expiry at `scheduledEndAt`.
