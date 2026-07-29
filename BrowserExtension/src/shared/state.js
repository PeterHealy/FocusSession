import {
  DEFAULT_BLOCKED_DOMAINS,
  matchedBlockedDomain,
  normalizeDomainList,
} from "./domains.js";

export const DEFAULT_FOCUS_SECONDS = 55 * 60;
export const DEFAULT_BREAK_SECONDS = 5 * 60;
export const SHOT_CLOCK_SECONDS = 10;
export const SHOT_CLOCK_EXTENSION_SECONDS = 30;

export function toEpochMilliseconds(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    // Be liberal at the protocol boundary: native code may send Unix seconds.
    return value < 10_000_000_000 ? Math.round(value * 1000) : Math.round(value);
  }

  if (typeof value === "string") {
    const numeric = Number(value);
    if (Number.isFinite(numeric) && value.trim() !== "") {
      return toEpochMilliseconds(numeric);
    }
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function boundedInteger(value, fallback, minimum, maximum) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return fallback;
  }
  return Math.min(maximum, Math.max(minimum, Math.round(numeric)));
}

function normalizedBreakDuration(value, fallback) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return fallback;
  }
  if (numeric === 0) {
    return 0;
  }
  return Math.min(60 * 60, Math.max(10, Math.round(numeric)));
}

export function inactiveState(overrides = {}) {
  return {
    active: false,
    profileName: "Deep Work",
    sessionId: null,
    startedAt: null,
    endAt: null,
    phase: "inactive",
    focusDurationSeconds: DEFAULT_FOCUS_SECONDS,
    breakDurationSeconds: DEFAULT_BREAK_SECONDS,
    nextBreakAvailableAt: null,
    breakAvailable: false,
    breakEndAt: null,
    blockedDomains: [...DEFAULT_BLOCKED_DOMAINS],
    updatedAt: 0,
    nativeCanExtendBreak: false,
    usageObservationEnabled: false,
    historyEnabled: false,
    ...overrides,
  };
}

export function normalizeSessionState(input, now = Date.now()) {
  if (!input || typeof input !== "object") {
    return inactiveState();
  }

  const focusDurationSeconds = boundedInteger(
    input.focusDurationSeconds,
    DEFAULT_FOCUS_SECONDS,
    60,
    24 * 60 * 60,
  );
  const breakDurationSeconds = normalizedBreakDuration(
    input.breakDurationSeconds,
    DEFAULT_BREAK_SECONDS,
  );
  const breaksEnabled = breakDurationSeconds > 0;
  const startedAt = toEpochMilliseconds(input.startedAt);
  const endAt = toEpochMilliseconds(input.endAt);
  const updatedAt = toEpochMilliseconds(input.updatedAt) ?? now;
  const blockedDomains = normalizeDomainList(
    input.blockedDomains,
    DEFAULT_BLOCKED_DOMAINS,
  );

  if (input.active !== true || endAt === null || endAt <= now) {
    return inactiveState({
      profileName:
        typeof input.profileName === "string" && input.profileName.trim()
          ? input.profileName.trim().slice(0, 80)
          : "Deep Work",
      blockedDomains:
        blockedDomains.length > 0
          ? blockedDomains
          : [...DEFAULT_BLOCKED_DOMAINS],
      focusDurationSeconds,
      breakDurationSeconds,
      updatedAt,
      usageObservationEnabled:
        input.usageObservationEnabled === true,
      historyEnabled: input.historyEnabled === true,
    });
  }

  const sessionStartedAt = startedAt ?? now;
  const requestedBreakEndAt = toEpochMilliseconds(input.breakEndAt);
  const breakEndAt =
    requestedBreakEndAt === null
      ? null
      : Math.min(requestedBreakEndAt, endAt);
  const phase =
    breaksEnabled &&
    input.phase === "break" &&
    breakEndAt !== null &&
    breakEndAt > now
      ? "break"
      : "focus";
  const fallbackNextBreakAt =
    breaksEnabled
      ? sessionStartedAt + focusDurationSeconds * 1000
      : null;
  let nextBreakAvailableAt =
    breaksEnabled
      ? toEpochMilliseconds(input.nextBreakAvailableAt) ??
        fallbackNextBreakAt
      : null;

  if (
    breaksEnabled &&
    input.phase === "break" &&
    requestedBreakEndAt !== null &&
    requestedBreakEndAt <= now
  ) {
    nextBreakAvailableAt = Math.max(
      nextBreakAvailableAt,
      requestedBreakEndAt + focusDurationSeconds * 1000,
    );
  }

  return {
    active: true,
    profileName:
      typeof input.profileName === "string" && input.profileName.trim()
        ? input.profileName.trim().slice(0, 80)
        : "Deep Work",
    sessionId:
      typeof input.sessionId === "string" && input.sessionId.trim()
        ? input.sessionId
        : null,
    startedAt: sessionStartedAt,
    endAt,
    phase,
    focusDurationSeconds,
    breakDurationSeconds,
    nextBreakAvailableAt,
    breakAvailable:
      breaksEnabled &&
      phase === "focus" &&
      (input.breakAvailable === true || nextBreakAvailableAt <= now),
    breakEndAt: phase === "break" ? breakEndAt : null,
    blockedDomains:
      blockedDomains.length > 0
        ? blockedDomains
        : [...DEFAULT_BLOCKED_DOMAINS],
    updatedAt,
    nativeCanExtendBreak: input.nativeCanExtendBreak === true,
    usageObservationEnabled: input.usageObservationEnabled === true,
    historyEnabled: input.historyEnabled === true,
  };
}

export function deriveSessionState(input, now = Date.now()) {
  const state = normalizeSessionState(input, now);
  if (!state.active) {
    return state;
  }

  if (state.phase === "break" && state.breakEndAt !== null) {
    if (state.breakEndAt > now) {
      return {
        ...state,
        breakEndAt: Math.min(state.breakEndAt, state.endAt),
      };
    }

    const nextBreakAvailableAt = Math.max(
      state.nextBreakAvailableAt ?? 0,
      state.breakEndAt + state.focusDurationSeconds * 1000,
    );
    return {
      ...state,
      phase: "focus",
      breakEndAt: null,
      nextBreakAvailableAt,
      breakAvailable: nextBreakAvailableAt <= now,
      updatedAt: now,
    };
  }

  return {
    ...state,
    breakAvailable:
      state.breakDurationSeconds > 0 &&
      (state.breakAvailable ||
        (state.nextBreakAvailableAt !== null &&
          state.nextBreakAvailableAt <= now)),
  };
}

export function shouldBlockWebsites(state, now = Date.now()) {
  const derived = deriveSessionState(state, now);
  return derived.active && derived.phase !== "break";
}

export function blockedDomainForUrl(
  state,
  url,
  now = Date.now(),
) {
  const derived = deriveSessionState(state, now);
  if (!derived.active || derived.phase === "break") {
    return null;
  }
  return matchedBlockedDomain(url, derived.blockedDomains);
}

export function breakRemainingMilliseconds(state, now = Date.now()) {
  const derived = deriveSessionState(state, now);
  if (
    !derived.active ||
    derived.phase !== "break" ||
    derived.breakEndAt === null
  ) {
    return 0;
  }
  return Math.max(0, Math.min(derived.breakEndAt, derived.endAt) - now);
}

export function canExtendBreak(state, now = Date.now()) {
  const derived = deriveSessionState(state, now);
  const remaining = breakRemainingMilliseconds(derived, now);
  return (
    remaining > 0 &&
    derived.breakEndAt < derived.endAt &&
    (remaining <= SHOT_CLOCK_SECONDS * 1000 ||
      derived.nativeCanExtendBreak === true)
  );
}

export function canStartBreak(state, now = Date.now()) {
  const derived = deriveSessionState(state, now);
  return (
    derived.active &&
    derived.breakDurationSeconds > 0 &&
    derived.phase === "focus" &&
    derived.breakAvailable === true
  );
}

export function sessionStatus(state, now = Date.now()) {
  const derived = deriveSessionState(state, now);
  if (!derived.active) {
    return "inactive";
  }
  if (derived.phase === "break") {
    return "break";
  }
  if (derived.breakAvailable) {
    return "break-available";
  }
  return "focus";
}

export function enforcementStateEquals(left, right, now = Date.now()) {
  const first = deriveSessionState(left, now);
  const second = deriveSessionState(right, now);
  const scalarKeys = [
    "active",
    "profileName",
    "sessionId",
    "startedAt",
    "endAt",
    "phase",
    "focusDurationSeconds",
    "breakDurationSeconds",
    "nextBreakAvailableAt",
    "breakAvailable",
    "breakEndAt",
    "usageObservationEnabled",
    "historyEnabled",
  ];
  if (scalarKeys.some((key) => first[key] !== second[key])) {
    return false;
  }
  return (
    first.blockedDomains.length === second.blockedDomains.length &&
    first.blockedDomains.every(
      (domain, index) => domain === second.blockedDomains[index],
    )
  );
}
