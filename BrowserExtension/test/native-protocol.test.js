import assert from "node:assert/strict";
import test from "node:test";

import {
  adaptNativeSessionState,
  buildNativeRequest,
  NATIVE_HOST_NAME,
  nativeResponseErrorMessage,
  splitActivitySeconds,
  stateSnapshotFromNativeMessage,
} from "../src/shared/native-protocol.js";

const NOW = Date.parse("2026-07-29T14:00:00.000Z");

test("native host identifier is fixed", () => {
  assert.equal(NATIVE_HOST_NAME, "com.focussession.nativehost");
});

test("native push state accepts wrapped and direct snapshots", () => {
  const snapshot = { isSessionActive: true, phase: "focusing" };
  assert.equal(
    stateSnapshotFromNativeMessage({ ok: true, state: snapshot }),
    snapshot,
  );
  assert.equal(stateSnapshotFromNativeMessage(snapshot), snapshot);
  assert.equal(stateSnapshotFromNativeMessage({ ok: true }), null);
});

test("structured native errors preserve their human-readable message", () => {
  assert.equal(
    nativeResponseErrorMessage({
      ok: false,
      error: { code: "notReady", message: "A break is not ready yet." },
    }),
    "A break is not ready yet.",
  );
});

test("native state names and phases adapt to cached browser enforcement", () => {
  const adapted = adaptNativeSessionState(
    {
      isSessionActive: true,
      sessionID: "native-session",
      startedAt: "2026-07-29T13:30:00.000Z",
      scheduledEndAt: "2026-07-29T18:00:00.000Z",
      generatedAt: "2026-07-29T14:00:00.000Z",
      phase: "breakAvailable",
      focusAvailableAt: "2026-07-29T13:55:00.000Z",
      breakEndsAt: null,
      canStartBreak: true,
      canExtendBreak: false,
      focusDurationSeconds: 3_300,
      breakDurationSeconds: 300,
      blockedDomains: ["reddit.com"],
      usageObservationEnabled: true,
      historyEnabled: false,
    },
    null,
    NOW,
  );
  assert.deepEqual(adapted, {
    active: true,
    profileName: "Deep Work",
    sessionId: "native-session",
    startedAt: Date.parse("2026-07-29T13:30:00.000Z"),
    endAt: Date.parse("2026-07-29T18:00:00.000Z"),
    phase: "focus",
    focusDurationSeconds: 3_300,
    breakDurationSeconds: 300,
    nextBreakAvailableAt: Date.parse("2026-07-29T13:55:00.000Z"),
    breakAvailable: true,
    breakEndAt: null,
    blockedDomains: ["reddit.com"],
    updatedAt: NOW,
    nativeCanExtendBreak: false,
    usageObservationEnabled: true,
    historyEnabled: false,
  });
});

test("onBreak maps to the browser break phase", () => {
  const adapted = adaptNativeSessionState(
    {
      isSessionActive: true,
      sessionID: "native-session",
      scheduledEndAt: NOW + 60_000,
      generatedAt: NOW,
      phase: "onBreak",
      breakEndsAt: NOW + 30_000,
    },
    null,
    NOW,
  );
  assert.equal(adapted.phase, "break");
  assert.equal(adapted.breakEndAt, NOW + 30_000);
});

test("native zero break duration survives protocol adaptation", () => {
  const adapted = adaptNativeSessionState(
    {
      isSessionActive: true,
      sessionID: "native-session",
      scheduledEndAt: NOW + 60_000,
      generatedAt: NOW,
      phase: "focusing",
      focusDurationSeconds: 3_300,
      breakDurationSeconds: 0,
    },
    null,
    NOW,
  );

  assert.equal(adapted.breakDurationSeconds, 0);
});

test("native mutation and event requests use the flat Swift schema", () => {
  assert.deepEqual(buildNativeRequest("getState"), { type: "getState" });
  assert.deepEqual(buildNativeRequest("startBreak", { sessionId: "ignored" }), {
    type: "startBreak",
  });
  assert.deepEqual(
    buildNativeRequest("recordBlockedAttempt", {
      domain: "old.reddit.com",
      sessionID: "session-1",
      wasOnBreak: false,
      historyEnabledAtObservation: true,
    }),
    {
      type: "recordBlockedAttempt",
      service: "reddit",
      domain: "old.reddit.com",
      attemptCount: 1,
      sessionID: "session-1",
      wasOnBreak: false,
      historyEnabledAtObservation: true,
    },
  );
  assert.deepEqual(
    buildNativeRequest("recordBlockedAttempt", {
      domain: "news.example.com",
    }),
    {
      type: "recordBlockedAttempt",
      service: "news.example.com",
      domain: "news.example.com",
      attemptCount: 1,
      sessionID: null,
      wasOnBreak: false,
      historyEnabledAtObservation: false,
    },
  );
  assert.deepEqual(
    buildNativeRequest("recordDomainActivity", {
      domain: "reddit.com",
      activeSeconds: 42,
      sessionID: "session-1",
      wasOnBreak: true,
      historyEnabledAtObservation: false,
    }),
    {
      type: "recordDomainActivity",
      domain: "reddit.com",
      activeSeconds: 42,
      sessionID: "session-1",
      wasOnBreak: true,
      historyEnabledAtObservation: false,
    },
  );
});

test("blocked-attempt aggregates are bounded native integers", () => {
  const request = (attemptCount) =>
    buildNativeRequest("recordBlockedAttempt", {
      domain: "reddit.com",
      attemptCount,
    });
  assert.equal(request(undefined).attemptCount, 1);
  assert.equal(request(0).attemptCount, 1);
  assert.equal(request(2.6).attemptCount, 3);
  assert.equal(request(25_000).attemptCount, 10_000);
  assert.equal(request(Number.NaN).attemptCount, 1);
});

test("history imports rename counts and serialize recency as ISO", () => {
  assert.deepEqual(
    buildNativeRequest("importHistorySummary", {
      historySummary: [
        { domain: "reddit.com", count: 7, lastVisitAt: NOW },
      ],
    }),
    {
      type: "importHistorySummary",
      historySummary: [
        {
          domain: "reddit.com",
          visitCount: 7,
          lastVisitAt: "2026-07-29T14:00:00.000Z",
        },
      ],
    },
  );
});

test("long activity periods split into native-safe chunks", () => {
  assert.deepEqual(splitActivitySeconds(7_250), [3_600, 3_600, 50]);
  assert.deepEqual(splitActivitySeconds(0), []);
});
