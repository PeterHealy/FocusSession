import {
  deriveSessionState,
  sessionStatus,
} from "../shared/state.js";
import {
  normalizeHostname,
  serviceForDomain,
} from "../shared/domains.js";

const elements = {
  title: document.querySelector("#page-title"),
  summary: document.querySelector("#summary"),
  sessionEnd: document.querySelector("#session-end"),
  timerLabel: document.querySelector("#timer-label"),
  timerValue: document.querySelector("#timer-value"),
  startBreak: document.querySelector("#start-break"),
  continueSite: document.querySelector("#continue-site"),
  goBack: document.querySelector("#go-back"),
  openApp: document.querySelector("#open-app"),
  openSettings: document.querySelector("#open-settings"),
  error: document.querySelector("#error"),
};

let state = null;
let timerId = null;
let continueTimerId = null;

function formatClock(timestamp) {
  if (!Number.isFinite(timestamp)) {
    return "—";
  }
  return new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(timestamp));
}

function formatDuration(milliseconds) {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function blockedDomain() {
  const requested = normalizeHostname(
    new URLSearchParams(window.location.search).get("domain"),
  );
  if (!requested || !Array.isArray(state?.blockedDomains)) {
    return null;
  }
  return state.blockedDomains.some(
    (domain) =>
      requested === domain || requested.endsWith(`.${domain}`),
  )
    ? requested
    : null;
}

function blockedServiceLabel() {
  const domain = blockedDomain();
  return serviceForDomain(domain)?.label ?? domain ?? "This site";
}

function continueTarget() {
  const domain = blockedDomain();
  return domain ? `https://${domain}/` : null;
}

function showContinueControl({ automatically = false } = {}) {
  const target = continueTarget();
  elements.continueSite.hidden = false;
  elements.continueSite.textContent = target
    ? `Continue to ${blockedServiceLabel()}`
    : "Return to site";
  if (!automatically || continueTimerId !== null) {
    return;
  }
  continueTimerId = window.setTimeout(() => {
    continueTimerId = null;
    continueToSite();
  }, 250);
}

function continueToSite() {
  const target = continueTarget();
  if (target) {
    window.location.replace(target);
  } else {
    window.history.back();
  }
}

function render() {
  const now = Date.now();
  const derived = deriveSessionState(state, now);
  const status = sessionStatus(derived, now);
  elements.sessionEnd.textContent = derived.active
    ? formatClock(derived.endAt)
    : "No active session";
  elements.startBreak.hidden = true;
  elements.continueSite.hidden = true;

  if (status === "inactive") {
    elements.title.textContent = `${blockedServiceLabel()} is available again.`;
    elements.summary.textContent =
      "The focus session has finished. Returning you now…";
    elements.timerLabel.textContent = "Status";
    elements.timerValue.textContent = "Complete";
    showContinueControl({ automatically: true });
    return;
  }

  if (status === "break") {
    elements.title.textContent = "Your free-use break is active.";
    elements.summary.textContent =
      `${blockedServiceLabel()} is available during your break. `
      + "Returning you now…";
    elements.timerLabel.textContent = "Break remaining";
    elements.timerValue.textContent = formatDuration(
      Math.min(derived.breakEndAt, derived.endAt) - now,
    );
    showContinueControl({ automatically: true });
    return;
  }

  elements.title.textContent = `${blockedServiceLabel()} is paused.`;
  if (status === "break-available") {
    elements.summary.textContent =
      `${derived.profileName} is keeping this site out of the way. `
      + "Your free-use break is ready when you want it.";
    elements.timerLabel.textContent = "Next break";
    elements.timerValue.textContent = "Available now";
    elements.startBreak.textContent =
      `Start ${formatDuration(derived.breakDurationSeconds * 1000)} break`;
    elements.startBreak.hidden = false;
    return;
  }

  elements.summary.textContent =
    derived.breakDurationSeconds === 0
      ? `${derived.profileName} is keeping this site out of the way `
        + "for the full session."
      : `${derived.profileName} is keeping this site out of the way `
        + "until your next break.";
  elements.timerLabel.textContent =
    derived.breakDurationSeconds === 0
      ? "Session remaining"
      : "Break available in";
  elements.timerValue.textContent = formatDuration(
    derived.breakDurationSeconds === 0
      ? derived.endAt - now
      : derived.nextBreakAvailableAt - now,
  );
}

async function loadState(refreshNative = false) {
  const response = await chrome.runtime.sendMessage({
    type: refreshNative ? "refreshState" : "getState",
  });
  if (!response?.ok) {
    throw new Error(response?.error || "Could not read the session.");
  }
  state = response.state;
  render();
}

elements.startBreak.addEventListener("click", async () => {
  elements.startBreak.disabled = true;
  elements.error.textContent = "";
  try {
    const response = await chrome.runtime.sendMessage({ type: "startBreak" });
    if (!response?.ok) {
      throw new Error(response?.error || "Could not start the break.");
    }
    state = response.state;
    render();
    window.setTimeout(() => window.history.back(), 120);
  } catch (error) {
    elements.error.textContent =
      error instanceof Error ? error.message : "Could not start the break.";
  } finally {
    elements.startBreak.disabled = false;
  }
});

elements.continueSite.addEventListener("click", continueToSite);

elements.goBack.addEventListener("click", () => {
  window.history.back();
});

elements.openApp.addEventListener("click", () => {
  // Custom-scheme navigation happens only in this explicit click handler.
  window.location.href = "focussession://open";
});

elements.openSettings.addEventListener("click", async () => {
  const response = await chrome.runtime.sendMessage({
    type: "openOptions",
  });
  if (!response?.ok) {
    elements.error.textContent =
      response?.error || "Could not open extension settings.";
  }
});

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "stateChanged") {
    state = message.state;
    render();
  }
});

loadState(true).catch((error) => {
  elements.error.textContent =
    error instanceof Error ? error.message : "Could not read the session.";
});
timerId = window.setInterval(render, 1000);
window.addEventListener(
  "pagehide",
  () => {
    window.clearInterval(timerId);
    if (continueTimerId !== null) {
      window.clearTimeout(continueTimerId);
    }
  },
  { once: true },
);
