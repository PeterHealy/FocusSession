import assert from "node:assert/strict";
import test from "node:test";

import {
  blockedDomainForUrl,
  canExtendBreak,
  canStartBreak,
  deriveSessionState,
  enforcementStateEquals,
  normalizeSessionState,
  sessionStatus,
  shouldBlockWebsites,
  toEpochMilliseconds,
} from "../src/shared/state.js";

const NOW = Date.parse("2026-07-29T14:00:00.000Z");

function focusState(overrides = {}) {
  return {
    active: true,
    sessionId: "session-1",
    startedAt: NOW,
    endAt: NOW + 4 * 60 * 60 * 1000,
    phase: "focus",
    focusDurationSeconds: 55 * 60,
    breakDurationSeconds: 5 * 60,
    nextBreakAvailableAt: NOW + 55 * 60 * 1000,
    breakAvailable: false,
    breakEndAt: null,
    blockedDomains: ["reddit.com"],
    updatedAt: NOW,
    usageObservationEnabled: true,
    historyEnabled: true,
    ...overrides,
  };
}

test("protocol timestamps accept milliseconds, seconds and ISO strings", () => {
  assert.equal(toEpochMilliseconds(NOW), NOW);
  assert.equal(toEpochMilliseconds(NOW / 1000), NOW);
  assert.equal(toEpochMilliseconds(new Date(NOW).toISOString()), NOW);
});

test("focus state blocks and earns a non-accumulating break by time", () => {
  const before = deriveSessionState(focusState(), NOW + 54 * 60 * 1000);
  assert.equal(shouldBlockWebsites(before, NOW + 54 * 60 * 1000), true);
  assert.equal(canStartBreak(before, NOW + 54 * 60 * 1000), false);

  const earned = deriveSessionState(focusState(), NOW + 55 * 60 * 1000);
  assert.equal(sessionStatus(earned, NOW + 55 * 60 * 1000), "break-available");
  assert.equal(canStartBreak(earned, NOW + 55 * 60 * 1000), true);
});

test("content fallback blocks restricted navigation only during focus", () => {
  const state = focusState({
    blockedDomains: ["x.com", "reddit.com"],
  });
  assert.equal(
    blockedDomainForUrl(state, "https://x.com/home", NOW),
    "x.com",
  );
  assert.equal(
    blockedDomainForUrl(state, "https://news.example.com/", NOW),
    null,
  );
  assert.equal(
    blockedDomainForUrl(
      {
        ...state,
        phase: "break",
        breakEndAt: NOW + 60_000,
      },
      "https://reddit.com/r/productivity",
      NOW,
    ),
    null,
  );
});

test("active break permits websites and exposes shot clock only at the end", () => {
  const state = focusState({
    phase: "break",
    breakAvailable: false,
    breakEndAt: NOW + 5 * 60 * 1000,
  });
  assert.equal(shouldBlockWebsites(state, NOW + 4 * 60 * 1000), false);
  assert.equal(canExtendBreak(state, NOW + 4 * 60 * 1000), false);
  assert.equal(canExtendBreak(state, NOW + 4 * 60 * 1000 + 50_001), true);
  assert.equal(
    canExtendBreak(
      {
        ...state,
        endAt: state.breakEndAt,
      },
      NOW + 4 * 60 * 1000 + 50_001,
    ),
    false,
  );
});

test("zero break duration keeps the whole session in focus", () => {
  const now = NOW + 2 * 60 * 60 * 1000;
  const noBreaks = deriveSessionState(
    focusState({
      breakDurationSeconds: 0,
      breakAvailable: true,
      nextBreakAvailableAt: NOW,
    }),
    now,
  );

  assert.equal(noBreaks.phase, "focus");
  assert.equal(noBreaks.breakDurationSeconds, 0);
  assert.equal(noBreaks.nextBreakAvailableAt, null);
  assert.equal(noBreaks.breakAvailable, false);
  assert.equal(canStartBreak(noBreaks, now), false);
  assert.equal(shouldBlockWebsites(noBreaks, now), true);
});

test("an expired break returns to focus and starts a fresh focus interval", () => {
  const breakEndAt = NOW + 5 * 60 * 1000;
  const expired = deriveSessionState(
    focusState({
      phase: "break",
      breakEndAt,
      nextBreakAvailableAt: NOW,
    }),
    breakEndAt + 1,
  );
  assert.equal(expired.phase, "focus");
  assert.equal(expired.breakAvailable, false);
  assert.equal(
    expired.nextBreakAvailableAt,
    breakEndAt + 55 * 60 * 1000,
  );
  assert.equal(shouldBlockWebsites(expired, breakEndAt + 1), true);
});

test("session expiry always disables cached enforcement", () => {
  const expired = normalizeSessionState(
    focusState({ endAt: NOW - 1 }),
    NOW,
  );
  assert.equal(expired.active, false);
  assert.equal(shouldBlockWebsites(expired, NOW), false);
});

test("break deadline is clamped to the absolute session end", () => {
  const state = normalizeSessionState(
    focusState({
      phase: "break",
      endAt: NOW + 20_000,
      breakEndAt: NOW + 60_000,
    }),
    NOW,
  );
  assert.equal(state.breakEndAt, NOW + 20_000);
});

test("generated-at-only native snapshots are enforcement-equivalent", () => {
  const first = focusState({ updatedAt: NOW });
  const second = focusState({
    updatedAt: NOW + 15_000,
    nativeCanExtendBreak: true,
  });
  assert.equal(enforcementStateEquals(first, second, NOW + 1_000), true);
  assert.equal(
    enforcementStateEquals(
      first,
      focusState({ endAt: first.endAt + 60_000 }),
      NOW + 1_000,
    ),
    false,
  );
});

test("native privacy flags survive inactive state and trigger state changes", () => {
  const inactive = normalizeSessionState(
    focusState({
      active: false,
      endAt: null,
      usageObservationEnabled: true,
      historyEnabled: false,
    }),
    NOW,
  );
  assert.equal(inactive.usageObservationEnabled, true);
  assert.equal(inactive.historyEnabled, false);
  assert.equal(
    enforcementStateEquals(
      focusState(),
      focusState({ usageObservationEnabled: false }),
      NOW + 1_000,
    ),
    false,
  );
  assert.equal(
    enforcementStateEquals(
      focusState(),
      focusState({ historyEnabled: false }),
      NOW + 1_000,
    ),
    false,
  );
});
