import {
  baseDomainFromUrl,
  matchedBlockedDomain,
  normalizeHostname,
  serviceForDomain,
} from "./shared/domains.js";
import { settleWithin } from "./shared/async.js";
import {
  blockedPageUrl,
  blockingRules,
  ownDynamicRuleIds,
} from "./shared/enforcement.js";
import { sanitizeHistorySummary } from "./shared/history-summary.js";
import {
  adaptNativeSessionState,
  buildNativeRequest,
  MAX_NATIVE_ATTEMPT_COUNT,
  NATIVE_HOST_NAME,
  nativeResponseErrorMessage,
  splitActivitySeconds,
  stateSnapshotFromNativeMessage,
} from "./shared/native-protocol.js";
import {
  canExtendBreak,
  canStartBreak,
  deriveSessionState,
  enforcementStateEquals,
  inactiveState,
  sessionStatus,
  shouldBlockWebsites,
} from "./shared/state.js";

const STORAGE_KEYS = Object.freeze({
  state: "cachedSessionState",
  nativeStatus: "nativeStatus",
  settings: "extensionSettings",
  activityBuffer: "domainActivityAggregates",
  attemptBuffer: "blockedAttemptAggregates",
  historyMeta: "historyAnalysisMeta",
});

const SESSION_KEYS = Object.freeze({
  activitySegment: "currentDomainActivitySegment",
});

const ALARMS = Object.freeze({
  sessionEnd: "focus-session:end",
  nextBreak: "focus-session:next-break",
  breakWarning: "focus-session:break-warning",
  breakEnd: "focus-session:break-end",
  stateSync: "focus-session:native-sync",
  aggregateFlush: "focus-session:aggregate-flush",
  nativeReconnect: "focus-session:native-reconnect",
});

const MANAGED_ALARMS = Object.freeze(
  Object.values(ALARMS).filter(
    (name) => name !== ALARMS.nativeReconnect,
  ),
);
const DEFAULT_SETTINGS = Object.freeze({
  observeDomainActivity: false,
});
const TAB_OPERATION_TIMEOUT_MILLISECONDS = 250;
const EXTENSION_ROOT_URL = chrome.runtime.getURL("/");

let currentState = inactiveState();
let initializationPromise = null;
let stateQueue = Promise.resolve();
let aggregateQueue = Promise.resolve();
let nativePushPort = null;
let nativeReconnectDelayMilliseconds = 1_000;
let nativePushMarkedConnected = false;

function serialiseStateWork(operation) {
  const result = stateQueue.catch(() => undefined).then(operation);
  stateQueue = result.catch(() => undefined);
  return result;
}

function serialiseAggregateWork(operation) {
  const result = aggregateQueue.catch(() => undefined).then(operation);
  aggregateQueue = result.catch(() => undefined);
  return result;
}

function safeErrorMessage(error) {
  if (error instanceof Error && error.message) {
    return error.message.slice(0, 300);
  }
  if (
    error &&
    typeof error === "object" &&
    typeof error.message === "string"
  ) {
    return error.message.slice(0, 300);
  }
  return String(error || "Unknown error").slice(0, 300);
}

async function updateNativeStatus(connected, error = null) {
  const status = {
    connected,
    checkedAt: Date.now(),
    lastConnectedAt: connected ? Date.now() : null,
    error: connected ? null : safeErrorMessage(error),
  };

  if (!connected) {
    const stored = await chrome.storage.local.get(STORAGE_KEYS.nativeStatus);
    status.lastConnectedAt =
      stored[STORAGE_KEYS.nativeStatus]?.lastConnectedAt ?? null;
  }

  await chrome.storage.local.set({
    [STORAGE_KEYS.nativeStatus]: status,
  });
  return status;
}

async function sendNativeRequest(type, payload = {}) {
  const message = buildNativeRequest(type, payload);

  try {
    const response = await chrome.runtime.sendNativeMessage(
      NATIVE_HOST_NAME,
      message,
    );
    if (!response || response.ok !== true) {
      throw new Error(
        nativeResponseErrorMessage(
          response,
          `Native request "${type}" failed.`,
        ),
      );
    }
    await updateNativeStatus(true);
    return response;
  } catch (error) {
    await updateNativeStatus(false, error);
    throw error;
  }
}

function scheduleNativePushReconnect(error) {
  void updateNativeStatus(false, error);
  chrome.alarms.create(ALARMS.nativeReconnect, {
    when: Date.now() + nativeReconnectDelayMilliseconds,
  });
  nativeReconnectDelayMilliseconds = Math.min(
    60_000,
    nativeReconnectDelayMilliseconds * 2,
  );
}

function connectNativePushPort() {
  if (nativePushPort !== null) {
    return;
  }

  let port;
  try {
    port = chrome.runtime.connectNative(NATIVE_HOST_NAME);
  } catch (error) {
    scheduleNativePushReconnect(error);
    return;
  }

  nativePushPort = port;
  void chrome.alarms.clear(ALARMS.nativeReconnect);

  port.onMessage.addListener((message) => {
    const nativeState = stateSnapshotFromNativeMessage(message);
    if (!nativeState) {
      if (message?.ok === false) {
        void updateNativeStatus(
          false,
          nativeResponseErrorMessage(message),
        );
      }
      return;
    }
    nativeReconnectDelayMilliseconds = 1_000;
    if (!nativePushMarkedConnected) {
      nativePushMarkedConnected = true;
      void updateNativeStatus(true);
    }
    void applyNativeSnapshot(nativeState).catch((error) =>
      updateNativeStatus(false, error),
    );
  });

  port.onDisconnect.addListener(() => {
    if (nativePushPort !== port) {
      return;
    }
    nativePushPort = null;
    nativePushMarkedConnected = false;
    const disconnectError =
      chrome.runtime.lastError?.message ??
      "Native push channel disconnected.";
    scheduleNativePushReconnect(disconnectError);
  });

  try {
    port.postMessage(buildNativeRequest("getState"));
  } catch (error) {
    try {
      port.disconnect();
    } catch {
      // The disconnect listener owns reconnect scheduling.
    }
    if (nativePushPort === port) {
      nativePushPort = null;
      scheduleNativePushReconnect(error);
    }
  }
}

async function cachedState() {
  const result = await chrome.storage.local.get(STORAGE_KEYS.state);
  return deriveSessionState(
    result[STORAGE_KEYS.state] ?? inactiveState(),
    Date.now(),
  );
}

async function extensionSettings() {
  const result = await chrome.storage.local.get(STORAGE_KEYS.settings);
  return {
    ...DEFAULT_SETTINGS,
    ...(result[STORAGE_KEYS.settings] ?? {}),
  };
}

function domainObservationIsEffective(
  settings,
  state = currentState,
) {
  return (
    settings.observeDomainActivity === true &&
    state.usageObservationEnabled === true
  );
}

function clearNativeDisabledBuffers(state) {
  if (state.usageObservationEnabled && state.historyEnabled) {
    return Promise.resolve();
  }
  return serialiseAggregateWork(async () => {
    if (!state.usageObservationEnabled) {
      await Promise.all([
        chrome.storage.session.remove(SESSION_KEYS.activitySegment),
        chrome.storage.local.remove(STORAGE_KEYS.activityBuffer),
      ]);
    }
    if (!state.historyEnabled) {
      await chrome.storage.local.remove(STORAGE_KEYS.attemptBuffer);
    }
  });
}

function clearDomainObservationData() {
  return serialiseAggregateWork(async () => {
    await Promise.all([
      chrome.storage.session.remove(SESSION_KEYS.activitySegment),
      chrome.storage.local.remove(STORAGE_KEYS.activityBuffer),
    ]);
  });
}

async function updateBlockingRules(state) {
  const installedRules =
    await chrome.declarativeNetRequest.getDynamicRules();
  const removeRuleIds = ownDynamicRuleIds(installedRules);
  const addRules = shouldBlockWebsites(state)
    ? blockingRules(state.blockedDomains, EXTENSION_ROOT_URL)
    : [];

  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds,
    addRules,
  });
}

async function enforceRestrictedTab(tab, state, reason) {
  if (tab.id === undefined) {
    return false;
  }
  return enforceRestrictedUrl(
    tab.id,
    tab.url,
    state,
    reason,
  );
}

async function enforceRestrictedUrl(
  tabId,
  url,
  state,
  reason,
) {
  const domain = matchedBlockedDomain(url, state.blockedDomains);
  if (!domain) {
    return false;
  }
  const result = await settleWithin(
    () =>
      chrome.tabs.update(tabId, {
        url: blockedPageUrl(EXTENSION_ROOT_URL, domain, reason),
      }),
    TAB_OPERATION_TIMEOUT_MILLISECONDS,
  );
  return result.status === "fulfilled";
}

async function blockOpenRestrictedTabs(state, reason = "focus") {
  if (!shouldBlockWebsites(state)) {
    return;
  }

  const tabs = await chrome.tabs.query({});
  await Promise.all(
    tabs.map((tab) => enforceRestrictedTab(tab, state, reason)),
  );
}

async function enforceTabById(tabId, reason) {
  await initialise();
  await reconcileCachedState();
  const state = deriveSessionState(currentState);
  if (!shouldBlockWebsites(state)) {
    return;
  }
  try {
    const tab = await chrome.tabs.get(tabId);
    await enforceRestrictedTab(tab, state, reason);
  } catch {
    // A tab can disappear between the browser event and enforcement.
  }
}

async function enforceFocusedWindow(reason) {
  await initialise();
  const windows = await chrome.windows.getAll({
    populate: true,
    windowTypes: ["normal"],
  });
  const focusedWindow = windows.find((window) => window.focused);
  const activeTab = focusedWindow?.tabs?.find((tab) => tab.active);
  if (activeTab?.id !== undefined) {
    await enforceTabById(activeTab.id, reason);
  }
}

async function broadcastState(state = currentState) {
  const nativeResult = await chrome.storage.local.get(
    STORAGE_KEYS.nativeStatus,
  );
  const message = {
    type: "stateChanged",
    state: deriveSessionState(state),
    nativeStatus: nativeResult[STORAGE_KEYS.nativeStatus] ?? null,
  };

  const tabs = await chrome.tabs.query({});
  await Promise.all(
    tabs.map(async (tab) => {
      if (tab.id === undefined) {
        return;
      }
      // Frozen/discarded Brave tabs can leave sendMessage pending forever.
      // State storage and DNR updates are authoritative, so tab delivery is
      // best-effort and must not pin the serialized enforcement queue.
      await settleWithin(
        () => chrome.tabs.sendMessage(tab.id, message),
        TAB_OPERATION_TIMEOUT_MILLISECONDS,
      );
    }),
  );
}

async function updateAction(state) {
  const status = sessionStatus(state);
  const badge =
    status === "inactive"
      ? ""
      : status === "break"
        ? "BREAK"
        : status === "break-available"
          ? "READY"
          : "FOCUS";
  const color =
    status === "break"
      ? "#2f855a"
      : status === "break-available"
        ? "#2563eb"
        : "#9f2d20";
  await chrome.action.setBadgeText({ text: badge });
  if (badge) {
    await chrome.action.setBadgeBackgroundColor({ color });
  }
}

async function resetManagedAlarms(state) {
  await Promise.all(MANAGED_ALARMS.map((name) => chrome.alarms.clear(name)));
  const now = Date.now();

  chrome.alarms.create(ALARMS.aggregateFlush, {
    delayInMinutes: state.active ? 1 : 5,
    periodInMinutes: state.active ? 1 : 5,
  });

  if (!state.active) {
    return;
  }

  chrome.alarms.create(ALARMS.sessionEnd, {
    when: Math.max(now + 100, state.endAt),
  });
  chrome.alarms.create(ALARMS.stateSync, {
    delayInMinutes: 1,
    periodInMinutes: 1,
  });

  if (
    state.phase === "focus" &&
    !state.breakAvailable &&
    state.nextBreakAvailableAt > now &&
    state.nextBreakAvailableAt < state.endAt
  ) {
    chrome.alarms.create(ALARMS.nextBreak, {
      when: state.nextBreakAvailableAt,
    });
  }

  if (state.phase === "break" && state.breakEndAt !== null) {
    const breakDeadline = Math.min(state.breakEndAt, state.endAt);
    if (breakDeadline - 10_000 > now) {
      chrome.alarms.create(ALARMS.breakWarning, {
        when: breakDeadline - 10_000,
      });
    }
    if (breakDeadline > now) {
      chrome.alarms.create(ALARMS.breakEnd, {
        when: breakDeadline,
      });
    }
  }
}

async function currentActivityContext(settings = null) {
  const effectiveSettings = settings ?? (await extensionSettings());
  if (!domainObservationIsEffective(effectiveSettings)) {
    return null;
  }

  const idleState = await chrome.idle.queryState(60);
  if (idleState !== "active") {
    return null;
  }

  const browserWindow = await chrome.windows.getLastFocused({
    windowTypes: ["normal"],
  });
  if (!browserWindow?.focused || browserWindow.id === undefined) {
    return null;
  }

  const [tab] = await chrome.tabs.query({
    active: true,
    windowId: browserWindow.id,
  });
  const domain = baseDomainFromUrl(tab?.url);
  if (!domain) {
    return null;
  }

  const state = deriveSessionState(currentState);
  return {
    domain,
    phase: state.active ? state.phase : "inactive",
    sessionId: state.active ? state.sessionId : null,
    historyEnabledAtObservation: state.historyEnabled === true,
  };
}

function sameActivityContext(left, right) {
  return (
    left?.domain === right?.domain &&
    left?.phase === right?.phase &&
    left?.sessionId === right?.sessionId &&
    left?.historyEnabledAtObservation ===
      right?.historyEnabledAtObservation
  );
}

function aggregateKey(entry) {
  return JSON.stringify([
    entry.sessionId ?? null,
    entry.phase,
    entry.domain,
    entry.historyEnabledAtObservation === true,
  ]);
}

function blockedAttemptKey(entry) {
  return JSON.stringify([
    entry.sessionId ?? null,
    entry.domain,
    entry.wasOnBreak === true,
    entry.historyEnabledAtObservation === true,
  ]);
}

async function appendActivityAggregate(entry) {
  const settings = await extensionSettings();
  if (!domainObservationIsEffective(settings)) {
    return;
  }
  const stored = await chrome.storage.local.get(STORAGE_KEYS.activityBuffer);
  const buffer = stored[STORAGE_KEYS.activityBuffer] ?? {};
  const key = aggregateKey(entry);
  const existing = buffer[key] ?? {
    sessionId: entry.sessionId ?? null,
    phase: entry.phase,
    domain: entry.domain,
    seconds: 0,
    lastActiveAt: 0,
    historyEnabledAtObservation:
      entry.historyEnabledAtObservation === true,
  };
  existing.seconds += entry.seconds;
  existing.lastActiveAt = Math.max(
    existing.lastActiveAt,
    entry.lastActiveAt,
  );
  buffer[key] = existing;
  await chrome.storage.local.set({
    [STORAGE_KEYS.activityBuffer]: buffer,
  });
}

function rollActivitySegment(force = false) {
  return serialiseAggregateWork(async () => {
    const now = Date.now();
    const stored = await chrome.storage.session.get(
      SESSION_KEYS.activitySegment,
    );
    const previous = stored[SESSION_KEYS.activitySegment] ?? null;
    const settings = await extensionSettings();
    const observationEffective =
      domainObservationIsEffective(settings);
    const nextContext = await currentActivityContext(settings);

    if (
      previous &&
      (force || !sameActivityContext(previous, nextContext))
    ) {
      const elapsedSeconds = Math.max(
        0,
        Math.floor((now - Number(previous.since)) / 1000),
      );
      if (
        observationEffective &&
        elapsedSeconds > 0 &&
        normalizeHostname(previous.domain) !== null
      ) {
        await appendActivityAggregate({
          sessionId: previous.sessionId ?? null,
          phase: previous.phase,
          domain: previous.domain,
          seconds: elapsedSeconds,
          lastActiveAt: now,
          historyEnabledAtObservation:
            previous.historyEnabledAtObservation === true,
        });
      }
    }

    if (!nextContext) {
      await chrome.storage.session.remove(SESSION_KEYS.activitySegment);
      return;
    }

    if (!force && previous && sameActivityContext(previous, nextContext)) {
      return;
    }

    await chrome.storage.session.set({
      [SESSION_KEYS.activitySegment]: {
        ...nextContext,
        since: now,
      },
    });
  });
}

function appendBlockedAttempt(domain, state) {
  if (state.historyEnabled !== true) {
    return Promise.resolve();
  }
  return serialiseAggregateWork(async () => {
    if (currentState.historyEnabled !== true) {
      return;
    }
    const stored = await chrome.storage.local.get(STORAGE_KEYS.attemptBuffer);
    const buffer = stored[STORAGE_KEYS.attemptBuffer] ?? {};
    const context = {
      sessionId: state.sessionId ?? null,
      domain,
      wasOnBreak: state.phase === "break",
      historyEnabledAtObservation:
        state.historyEnabled === true,
    };
    const key = blockedAttemptKey(context);
    const existing = buffer[key] ?? {
      ...context,
      count: 0,
      lastAttemptAt: 0,
    };
    existing.count = Math.min(
      MAX_NATIVE_ATTEMPT_COUNT,
      existing.count + 1,
    );
    existing.lastAttemptAt = Date.now();
    buffer[key] = existing;
    await chrome.storage.local.set({
      [STORAGE_KEYS.attemptBuffer]: buffer,
    });
  });
}

async function flushAggregateBufferNow() {
  const stored = await chrome.storage.local.get([
    STORAGE_KEYS.activityBuffer,
    STORAGE_KEYS.attemptBuffer,
  ]);
  const activities = Object.values(
    stored[STORAGE_KEYS.activityBuffer] ?? {},
  );
  const attempts = Object.values(stored[STORAGE_KEYS.attemptBuffer] ?? {});
  const failedActivities = {};
  const failedAttempts = {};
  let nativeUnavailable = false;
  const settings = await extensionSettings();

  for (const activity of activities) {
    if (!domainObservationIsEffective(settings)) {
      continue;
    }
    if (nativeUnavailable) {
      failedActivities[aggregateKey(activity)] = activity;
      continue;
    }
    const chunks = splitActivitySeconds(activity.seconds);
    let chunkIndex = 0;
    try {
      for (; chunkIndex < chunks.length; chunkIndex += 1) {
        if (!domainObservationIsEffective(settings)) {
          chunkIndex = chunks.length;
          break;
        }
        await sendNativeRequest("recordDomainActivity", {
          domain: activity.domain,
          activeSeconds: chunks[chunkIndex],
          sessionID: activity.sessionId,
          wasOnBreak: activity.phase === "break",
          historyEnabledAtObservation:
            activity.historyEnabledAtObservation === true,
        });
      }
    } catch {
      nativeUnavailable = true;
      failedActivities[aggregateKey(activity)] = {
        ...activity,
        seconds: chunks
          .slice(chunkIndex)
          .reduce((total, seconds) => total + seconds, 0),
      };
    }
  }

  for (const attempt of attempts) {
    const key = blockedAttemptKey(attempt);
    if (currentState.historyEnabled !== true) {
      continue;
    }
    if (nativeUnavailable) {
      failedAttempts[key] = attempt;
      continue;
    }
    try {
      await sendNativeRequest("recordBlockedAttempt", {
        domain: attempt.domain,
        service: serviceForDomain(attempt.domain)?.id,
        attemptCount: attempt.count,
        sessionID: attempt.sessionId,
        wasOnBreak: attempt.wasOnBreak === true,
        historyEnabledAtObservation:
          attempt.historyEnabledAtObservation === true,
      });
    } catch {
      nativeUnavailable = true;
      failedAttempts[key] = attempt;
    }
  }

  await chrome.storage.local.set({
    [STORAGE_KEYS.activityBuffer]: failedActivities,
    [STORAGE_KEYS.attemptBuffer]: failedAttempts,
  });
}

function flushAggregates() {
  return rollActivitySegment(true).then(() =>
    serialiseAggregateWork(flushAggregateBufferNow),
  );
}

async function applySessionState(rawState, options = {}) {
  return serialiseStateWork(async () => {
    const previous = currentState;
    const state = deriveSessionState(rawState, Date.now());
    currentState = state;
    const privacyClearPromise = clearNativeDisabledBuffers(state);

    await chrome.storage.local.set({
      [STORAGE_KEYS.state]: state,
    });
    await updateBlockingRules(state);
    await resetManagedAlarms(state);
    await updateAction(state);

    const becameBlocking =
      shouldBlockWebsites(state) &&
      (!shouldBlockWebsites(previous) ||
        previous.phase === "break" ||
        options.forceOpenTabCheck === true);
    if (becameBlocking) {
      await blockOpenRestrictedTabs(state, options.reason ?? "focus");
    }
    await privacyClearPromise;

    // The stored activity segment already carries its original phase/session,
    // so rolling it can happen after enforcement without delaying a pushed
    // Start Session event behind aggregate I/O.
    void rollActivitySegment(false);
    if (options.broadcast !== false) {
      await broadcastState(state);
    }
    return state;
  });
}

async function applyNativeSnapshot(nativeState, options = {}) {
  // Apply a local wall-clock boundary before comparing native snapshots.
  // Otherwise both sides can derive to the same phase while DNR still
  // represents the pre-boundary phase (for example, just after a break ends).
  await reconcileCachedState();
  const adapted = adaptNativeSessionState(nativeState, currentState);
  if (enforcementStateEquals(currentState, adapted, Date.now())) {
    currentState = deriveSessionState(currentState, Date.now());
    return currentState;
  }
  return applySessionState(adapted, options);
}

async function reconcileCachedState() {
  const derived = deriveSessionState(currentState, Date.now());
  const crossedBoundary =
    derived.active !== currentState.active ||
    derived.phase !== currentState.phase ||
    derived.breakAvailable !== currentState.breakAvailable;
  if (crossedBoundary) {
    return applySessionState(derived);
  }
  currentState = derived;
  return currentState;
}

async function refreshStateFromNative() {
  try {
    const response = await sendNativeRequest("getState");
    const nativeState = stateSnapshotFromNativeMessage(response);
    if (!nativeState) {
      throw new Error("The native host returned no session state.");
    }
    return await applyNativeSnapshot(nativeState);
  } catch {
    return await applySessionState(currentState, {
      forceOpenTabCheck: true,
    });
  }
}

async function performNativeMutation(type) {
  const state = deriveSessionState(currentState);
  if (type === "startBreak" && !canStartBreak(state)) {
    throw new Error("A break is not available yet.");
  }
  if (type === "extendBreak" && !canExtendBreak(state)) {
    throw new Error("The +30 second control is available in the final 10 seconds.");
  }

  const response = await sendNativeRequest(type, {
    sessionId: state.sessionId,
  });
  let nativeState = stateSnapshotFromNativeMessage(response);
  if (!nativeState) {
    const refreshed = await sendNativeRequest("getState");
    nativeState = stateSnapshotFromNativeMessage(refreshed);
  }
  if (!nativeState) {
    throw new Error("The native host accepted the action but returned no state.");
  }

  return await applyNativeSnapshot(nativeState, {
    reason: type === "startBreak" ? "break-started" : "break-extended",
  });
}

async function publicStatus() {
  const result = await chrome.storage.local.get([
    STORAGE_KEYS.nativeStatus,
    STORAGE_KEYS.historyMeta,
  ]);
  return {
    ok: true,
    state: deriveSessionState(currentState),
    nativeStatus: result[STORAGE_KEYS.nativeStatus] ?? null,
    historyAnalysis: result[STORAGE_KEYS.historyMeta] ?? null,
  };
}

async function importHistorySummary(message) {
  if (!currentState.usageObservationEnabled) {
    throw new Error(
      "Usage observation is disabled in the FocusSession macOS app.",
    );
  }
  const summary = sanitizeHistorySummary(message?.domains);
  if (summary.length === 0) {
    throw new Error("No eligible browser history was found.");
  }

  const analysedAt = Date.now();
  await sendNativeRequest("importHistorySummary", {
    historySummary: summary,
  });
  const meta = {
    analysedAt,
    domainCount: summary.length,
  };
  await chrome.storage.local.set({
    [STORAGE_KEYS.historyMeta]: meta,
  });
  return { ok: true, historyAnalysis: meta };
}

async function handleMessage(message) {
  const type = message?.type;
  switch (type) {
    case "getState":
      await reconcileCachedState();
      return publicStatus();
    case "refreshState":
      await refreshStateFromNative();
      return publicStatus();
    case "startBreak":
      await performNativeMutation("startBreak");
      return publicStatus();
    case "extendBreak":
      await performNativeMutation("extendBreak");
      return publicStatus();
    case "importHistorySummary":
      return importHistorySummary(message);
    case "enforceNow":
      await applySessionState(currentState, {
        forceOpenTabCheck: true,
        reason: "break-ended",
      });
      return publicStatus();
    case "getSettings": {
      const settings = await extensionSettings();
      return {
        ok: true,
        settings,
        nativePrivacy: {
          usageObservationEnabled:
            currentState.usageObservationEnabled === true,
          historyEnabled: currentState.historyEnabled === true,
          effectiveDomainObservation:
            domainObservationIsEffective(settings),
        },
      };
    }
    case "setObserveDomainActivity": {
      const settings = {
        ...(await extensionSettings()),
        observeDomainActivity: message.enabled === true,
      };
      await chrome.storage.local.set({
        [STORAGE_KEYS.settings]: settings,
      });
      if (!settings.observeDomainActivity) {
        await clearDomainObservationData();
      } else {
        await rollActivitySegment(false);
      }
      return { ok: true, settings };
    }
    case "openOptions":
      await chrome.runtime.openOptionsPage();
      return { ok: true };
    default:
      throw new Error("Unsupported extension request.");
  }
}

async function initialise() {
  if (initializationPromise) {
    return initializationPromise;
  }

  initializationPromise = (async () => {
    chrome.idle.setDetectionInterval(60);
    currentState = await cachedState();
    await applySessionState(currentState, {
      broadcast: false,
      forceOpenTabCheck: true,
    });
    connectNativePushPort();
    await refreshStateFromNative();
    await rollActivitySegment(false);
  })().catch((error) => {
    initializationPromise = null;
    throw error;
  });
  return initializationPromise;
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  initialise()
    .then(() => handleMessage(message))
    .then(sendResponse)
    .catch((error) =>
      sendResponse({
        ok: false,
        error: safeErrorMessage(error),
      }),
    );
  return true;
});

chrome.runtime.onInstalled.addListener(() => {
  void initialise();
});

chrome.runtime.onStartup.addListener(() => {
  void initialise();
});

chrome.alarms.onAlarm.addListener((alarm) => {
  void initialise().then(async () => {
    if (alarm.name === ALARMS.nativeReconnect) {
      connectNativePushPort();
      return;
    }

    if (alarm.name === ALARMS.breakWarning) {
      await broadcastState();
      return;
    }

    if (
      alarm.name === ALARMS.sessionEnd ||
      alarm.name === ALARMS.nextBreak ||
      alarm.name === ALARMS.breakEnd
    ) {
      const reason =
        alarm.name === ALARMS.breakEnd ? "break-ended" : "timer";
      await applySessionState(currentState, {
        forceOpenTabCheck: true,
        reason,
      });
      void refreshStateFromNative();
      return;
    }

    if (alarm.name === ALARMS.stateSync) {
      await flushAggregates();
      await refreshStateFromNative();
      return;
    }

    if (alarm.name === ALARMS.aggregateFlush) {
      await flushAggregates();
    }
  });
});

chrome.webNavigation.onBeforeNavigate.addListener((details) => {
  if (details.frameId !== 0) {
    return;
  }
  const state = deriveSessionState(currentState);
  if (!shouldBlockWebsites(state)) {
    return;
  }
  const domain = matchedBlockedDomain(details.url, state.blockedDomains);
  if (domain) {
    void appendBlockedAttempt(domain, state);
    // Brave can cancel a DNR-intercepted navigation before replacing the
    // previous document, leaving the new domain in the address bar while old
    // content remains visible. Move the tab to the local page immediately
    // from the navigation event so the user always sees the focus explanation.
    void enforceRestrictedUrl(
      details.tabId,
      details.url,
      state,
      "navigation-start",
    );
  }
});

chrome.tabs.onActivated.addListener((activeInfo) => {
  void rollActivitySegment(false);
  void enforceTabById(activeInfo.tabId, "tab-activated");
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (tab.active && (changeInfo.url || changeInfo.status === "complete")) {
    void rollActivitySegment(false);
  }
  if (changeInfo.url) {
    const state = deriveSessionState(currentState);
    if (shouldBlockWebsites(state)) {
      void enforceRestrictedUrl(
        tabId,
        changeInfo.url,
        state,
        "tab-navigation",
      );
    }
  } else if (changeInfo.status === "complete") {
    void enforceTabById(tabId, "tab-navigation");
  }
});

chrome.tabs.onRemoved.addListener(() => {
  void rollActivitySegment(false);
});

chrome.windows.onFocusChanged.addListener(() => {
  void rollActivitySegment(false);
  void enforceFocusedWindow("window-focused");
});

chrome.idle.onStateChanged.addListener(() => {
  void rollActivitySegment(false);
});

void initialise();
