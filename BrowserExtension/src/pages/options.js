import {
  addVisitToAccumulator,
  createHistoryAccumulator,
  finalizeHistorySummary,
  HISTORY_ANALYSIS_DAYS,
} from "../shared/history-summary.js";

const elements = {
  connection: document.querySelector("#connection"),
  refresh: document.querySelector("#refresh"),
  domains: document.querySelector("#domains"),
  manageRestrictions: document.querySelector("#manage-restrictions"),
  observeActivity: document.querySelector("#observe-activity"),
  activityPolicy: document.querySelector("#activity-policy"),
  analyseHistory: document.querySelector("#analyse-history"),
  removeHistory: document.querySelector("#remove-history"),
  historyPolicy: document.querySelector("#history-policy"),
  historyStatus: document.querySelector("#history-status"),
  error: document.querySelector("#error"),
};

let nativeUsageObservationEnabled = false;

elements.manageRestrictions.addEventListener("click", () => {
  window.location.href = "focussession://open";
});

function displayDate(timestamp) {
  if (!Number.isFinite(timestamp)) {
    return "";
  }
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(timestamp));
}

function renderStatus(response) {
  elements.connection.textContent = response.nativeStatus?.connected
    ? "Connected to the Focus Session macOS app."
    : `The native app is unavailable. Cached session rules remain enforced.${
        response.nativeStatus?.error
          ? ` ${response.nativeStatus.error}`
          : ""
      }`;

  elements.domains.replaceChildren();
  for (const domain of response.state?.blockedDomains ?? []) {
    const item = document.createElement("li");
    item.textContent = domain;
    elements.domains.appendChild(item);
  }

  if (response.historyAnalysis?.analysedAt) {
    elements.historyStatus.textContent = `Last analysed ${displayDate(
      response.historyAnalysis.analysedAt,
    )}; ${response.historyAnalysis.domainCount} base domains imported.`;
  }

  nativeUsageObservationEnabled =
    response.state?.usageObservationEnabled === true;
  const nativeSessionHistoryEnabled =
    response.state?.historyEnabled === true;
  elements.observeActivity.disabled =
    !nativeUsageObservationEnabled;
  elements.activityPolicy.textContent = nativeUsageObservationEnabled
    ? "Allowed by the macOS app; this extension switch can still turn it off."
    : "Disabled by the macOS app. The extension cannot override it.";
  if (!nativeUsageObservationEnabled) {
    elements.historyPolicy.textContent =
      "Usage observation is disabled by the macOS app, so browser-history analysis is unavailable.";
  } else if (!nativeSessionHistoryEnabled) {
    elements.historyPolicy.textContent =
      "Browser-history analysis is allowed. Session history is off, so blocked-attempt totals are not retained.";
  } else {
    elements.historyPolicy.textContent =
      "Browser-history analysis and blocked-attempt session totals are allowed by the macOS app.";
  }
  elements.analyseHistory.disabled =
    !nativeUsageObservationEnabled;
}

async function refresh() {
  const [status, settings, hasHistoryPermission] = await Promise.all([
    chrome.runtime.sendMessage({ type: "refreshState" }),
    chrome.runtime.sendMessage({ type: "getSettings" }),
    chrome.permissions.contains({ permissions: ["history"] }),
  ]);
  if (!status?.ok) {
    throw new Error(status?.error || "Could not read extension status.");
  }
  if (!settings?.ok) {
    throw new Error(settings?.error || "Could not read privacy settings.");
  }
  renderStatus(status);
  elements.observeActivity.checked =
    settings.settings.observeDomainActivity === true;
  elements.removeHistory.hidden = !hasHistoryPermission;
}

async function pooledMap(items, concurrency, operation) {
  let cursor = 0;
  async function worker() {
    while (cursor < items.length) {
      const index = cursor;
      cursor += 1;
      await operation(items[index]);
    }
  }
  await Promise.all(
    Array.from(
      { length: Math.min(concurrency, Math.max(1, items.length)) },
      worker,
    ),
  );
}

async function analyseHistory() {
  if (!nativeUsageObservationEnabled) {
    throw new Error(
      "Usage observation is disabled in the FocusSession macOS app.",
    );
  }
  elements.error.textContent = "";
  elements.historyStatus.textContent =
    "Waiting for browser history permission…";

  const granted = await chrome.permissions.request({
    permissions: ["history"],
  });
  if (!granted) {
    elements.historyStatus.textContent =
      "History permission was not granted. Nothing was analysed.";
    return;
  }

  elements.removeHistory.hidden = false;
  elements.historyStatus.textContent =
    "Analysing locally. This can take a moment…";
  const cutoff = Date.now() - HISTORY_ANALYSIS_DAYS * 24 * 60 * 60 * 1000;
  const historyItems = await chrome.history.search({
    text: "",
    startTime: cutoff,
    maxResults: 100_000,
  });
  const accumulator = createHistoryAccumulator();

  await pooledMap(historyItems, 12, async (item) => {
    // The complete URL is used only as an ephemeral key for getVisits. It is
    // neither logged nor sent through extension messaging.
    const visits = await chrome.history.getVisits({ url: item.url });
    for (const visit of visits) {
      addVisitToAccumulator(
        accumulator,
        item.url,
        visit.visitTime,
        cutoff,
      );
    }
  });

  // Drop references to browser HistoryItem objects, including titles and URLs,
  // before sending the domain-only result.
  historyItems.length = 0;
  const domains = finalizeHistorySummary(accumulator);
  accumulator.clear();
  if (domains.length === 0) {
    elements.historyStatus.textContent =
      "No eligible HTTP or HTTPS visits were found.";
    return;
  }

  const response = await chrome.runtime.sendMessage({
    type: "importHistorySummary",
    domains,
  });
  domains.length = 0;
  if (!response?.ok) {
    throw new Error(response?.error || "Could not import the local summary.");
  }
  elements.historyStatus.textContent = `Imported ${
    response.historyAnalysis.domainCount
  } base domains at ${displayDate(response.historyAnalysis.analysedAt)}.`;
}

elements.refresh.addEventListener("click", () => {
  elements.error.textContent = "";
  refresh().catch((error) => {
    elements.error.textContent =
      error instanceof Error ? error.message : "Could not refresh.";
  });
});

elements.observeActivity.addEventListener("change", async () => {
  const response = await chrome.runtime.sendMessage({
    type: "setObserveDomainActivity",
    enabled: elements.observeActivity.checked,
  });
  if (!response?.ok) {
    elements.observeActivity.checked = !elements.observeActivity.checked;
    elements.error.textContent =
      response?.error || "Could not update the privacy setting.";
  }
});

elements.analyseHistory.addEventListener("click", () => {
  elements.analyseHistory.disabled = true;
  analyseHistory()
    .catch((error) => {
      elements.error.textContent =
        error instanceof Error ? error.message : "History analysis failed.";
      elements.historyStatus.textContent = "No history data was imported.";
    })
    .finally(() => {
      elements.analyseHistory.disabled =
        !nativeUsageObservationEnabled;
    });
});

elements.removeHistory.addEventListener("click", async () => {
  const removed = await chrome.permissions.remove({
    permissions: ["history"],
  });
  if (removed) {
    elements.removeHistory.hidden = true;
    elements.historyStatus.textContent =
      "History permission removed. Previously imported domain aggregates remain in the macOS app until cleared there.";
  }
});

refresh().catch((error) => {
  elements.error.textContent =
    error instanceof Error ? error.message : "Could not load settings.";
});
