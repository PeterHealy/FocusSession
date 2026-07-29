import {
  normalizeHostname,
  serviceForDomain,
} from "./domains.js";
import {
  DEFAULT_BREAK_SECONDS,
  DEFAULT_FOCUS_SECONDS,
  toEpochMilliseconds,
} from "./state.js";

export const NATIVE_HOST_NAME = "com.focussession.nativehost";
export const MAX_NATIVE_ACTIVITY_SECONDS = 3_600;
export const MAX_NATIVE_ATTEMPT_COUNT = 10_000;

function nativeDuration(value, fallback, { allowZero = false } = {}) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric < 0) {
    return fallback;
  }
  if (numeric === 0 && !allowZero) {
    return fallback;
  }
  return numeric;
}

const NATIVE_PHASES = new Set([
  "inactive",
  "focusing",
  "breakAvailable",
  "onBreak",
]);

export function adaptNativeSessionState(
  nativeState,
  cachedState = null,
  now = Date.now(),
) {
  if (!nativeState || typeof nativeState !== "object") {
    throw new TypeError("Native session state is missing.");
  }

  const nativePhase = NATIVE_PHASES.has(nativeState.phase)
    ? nativeState.phase
    : "inactive";
  const sessionId =
    typeof nativeState.sessionID === "string" &&
    nativeState.sessionID.trim()
      ? nativeState.sessionID
      : null;
  const sameSession =
    sessionId !== null && cachedState?.sessionId === sessionId;
  const generatedAt =
    toEpochMilliseconds(nativeState.generatedAt) ?? now;

  return {
    active:
      nativeState.isSessionActive === true &&
      nativePhase !== "inactive",
    profileName:
      typeof nativeState.profileName === "string" &&
      nativeState.profileName.trim()
        ? nativeState.profileName.trim().slice(0, 80)
        : cachedState?.profileName ?? "Deep Work",
    sessionId,
    startedAt:
      toEpochMilliseconds(nativeState.startedAt) ??
      (sameSession ? cachedState.startedAt : generatedAt),
    endAt: toEpochMilliseconds(nativeState.scheduledEndAt),
    phase: nativePhase === "onBreak" ? "break" : "focus",
    focusDurationSeconds:
      nativeDuration(
        nativeState.focusDurationSeconds,
        cachedState?.focusDurationSeconds ?? DEFAULT_FOCUS_SECONDS,
      ),
    breakDurationSeconds:
      nativeDuration(
        nativeState.breakDurationSeconds,
        cachedState?.breakDurationSeconds ?? DEFAULT_BREAK_SECONDS,
        { allowZero: true },
      ),
    nextBreakAvailableAt: toEpochMilliseconds(
      nativeState.focusAvailableAt,
    ),
    breakAvailable:
      nativePhase === "breakAvailable" ||
      nativeState.canStartBreak === true,
    breakEndAt: toEpochMilliseconds(nativeState.breakEndsAt),
    blockedDomains: nativeState.blockedDomains,
    updatedAt: generatedAt,
    nativeCanExtendBreak: nativeState.canExtendBreak === true,
    usageObservationEnabled:
      nativeState.usageObservationEnabled === true,
    historyEnabled: nativeState.historyEnabled === true,
  };
}

export function stateSnapshotFromNativeMessage(message) {
  if (!message || typeof message !== "object") {
    return null;
  }
  const wrapped = message.state ?? message.payload?.state;
  if (wrapped && typeof wrapped === "object") {
    return wrapped;
  }
  return Object.hasOwn(message, "isSessionActive") ? message : null;
}

export function nativeResponseErrorMessage(
  response,
  fallback = "The native request failed.",
) {
  const error = response?.error;
  if (typeof error === "string" && error.trim()) {
    return error.trim();
  }
  if (
    error &&
    typeof error === "object" &&
    typeof error.message === "string" &&
    error.message.trim()
  ) {
    return error.message.trim();
  }
  return fallback;
}

function cleanDomain(value) {
  const domain = normalizeHostname(value);
  if (!domain) {
    throw new TypeError("A valid base domain is required.");
  }
  return domain;
}

function historyEntry(entry) {
  const domain = cleanDomain(entry?.domain);
  const visitCount = Math.round(
    Number(entry?.visitCount ?? entry?.count),
  );
  const timestamp = toEpochMilliseconds(entry?.lastVisitAt);
  if (
    !Number.isFinite(visitCount) ||
    visitCount <= 0 ||
    timestamp === null
  ) {
    throw new TypeError("History summary entries must include count and recency.");
  }
  return {
    domain,
    visitCount,
    lastVisitAt: new Date(timestamp).toISOString(),
  };
}

export function buildNativeRequest(type, data = {}) {
  switch (type) {
    case "getState":
    case "startBreak":
    case "extendBreak":
      return { type };
    case "recordBlockedAttempt": {
      const domain = cleanDomain(data.domain);
      const service =
        (typeof data.service === "string" && data.service.trim()
          ? data.service.trim()
          : null) ??
        serviceForDomain(domain)?.id ??
        domain;
      const requestedCount = Number(data.attemptCount ?? 1);
      const attemptCount = Number.isFinite(requestedCount)
        ? Math.min(
            MAX_NATIVE_ATTEMPT_COUNT,
            Math.max(1, Math.round(requestedCount)),
          )
        : 1;
      return {
        type,
        service,
        domain,
        attemptCount,
        sessionID:
          typeof (data.sessionID ?? data.sessionId) === "string" &&
          (data.sessionID ?? data.sessionId).trim()
            ? (data.sessionID ?? data.sessionId).trim()
            : null,
        wasOnBreak:
          data.wasOnBreak === true || data.phase === "break",
        historyEnabledAtObservation:
          data.historyEnabledAtObservation === true,
      };
    }
    case "recordDomainActivity":
      return {
        type,
        domain: cleanDomain(data.domain),
        activeSeconds: Math.min(
          MAX_NATIVE_ACTIVITY_SECONDS,
          Math.max(
            1,
            Math.round(Number(data.activeSeconds ?? data.seconds)),
          ),
        ),
        sessionID:
          typeof (data.sessionID ?? data.sessionId) === "string" &&
          (data.sessionID ?? data.sessionId).trim()
            ? (data.sessionID ?? data.sessionId).trim()
            : null,
        wasOnBreak:
          data.wasOnBreak === true || data.phase === "break",
        historyEnabledAtObservation:
          data.historyEnabledAtObservation === true,
      };
    case "importHistorySummary":
      return {
        type,
        historySummary: (Array.isArray(data.historySummary)
          ? data.historySummary
          : data.domains ?? []
        ).map(historyEntry),
      };
    default:
      throw new TypeError(`Unsupported native request type: ${type}`);
  }
}

export function splitActivitySeconds(value) {
  let remaining = Math.max(0, Math.round(Number(value)));
  if (!Number.isFinite(remaining) || remaining === 0) {
    return [];
  }
  const chunks = [];
  while (remaining > 0) {
    const chunk = Math.min(MAX_NATIVE_ACTIVITY_SECONDS, remaining);
    chunks.push(chunk);
    remaining -= chunk;
  }
  return chunks;
}
