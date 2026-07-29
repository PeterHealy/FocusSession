(() => {
  "use strict";

  const ROOT_ID = "focus-session-shot-clock";
  const FINAL_SECONDS = 10;
  let sessionState = null;
  let root = null;
  let shadow = null;
  let countdown = null;
  let extensionButton = null;
  let message = null;
  let renderTimerId = null;
  let expiryHandledFor = null;

  function normalizedHostname(value) {
    return String(value || "")
      .trim()
      .toLowerCase()
      .replace(/^\.+|\.+$/g, "");
  }

  function restrictedDomainForCurrentPage(state) {
    const hostname = normalizedHostname(window.location.hostname);
    if (!hostname || !Array.isArray(state?.blockedDomains)) {
      return null;
    }
    return state.blockedDomains.find((value) => {
      const domain = normalizedHostname(value);
      return (
        domain &&
        (hostname === domain || hostname.endsWith(`.${domain}`))
      );
    }) ?? null;
  }

  function currentPageIsRestricted(state) {
    return restrictedDomainForCurrentPage(state) !== null;
  }

  function enforceRestrictedPage(state) {
    const domain = restrictedDomainForCurrentPage(state);
    if (!domain) {
      return false;
    }
    const target = new URL(
      chrome.runtime.getURL("src/pages/blocked.html"),
    );
    target.searchParams.set("domain", domain);
    target.searchParams.set("reason", "page-enforcement");
    window.location.replace(target.toString());
    return true;
  }

  function createOverlay() {
    if (root) {
      if (!root.isConnected) {
        (document.documentElement || document.body).appendChild(root);
      }
      return;
    }
    root = document.createElement("div");
    root.id = ROOT_ID;
    root.style.setProperty("all", "initial", "important");
    root.style.setProperty("display", "none", "important");
    shadow = root.attachShadow({ mode: "closed" });
    shadow.innerHTML = `
      <style>
        :host { all: initial; }
        .card {
          align-items: center;
          background: #181713;
          border: 1px solid rgba(255,255,255,.18);
          border-radius: 14px;
          box-shadow: 0 16px 50px rgba(0,0,0,.34);
          color: #fffdf7;
          display: flex;
          font: 600 14px/1.25 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          gap: 12px;
          max-width: calc(100vw - 32px);
          padding: 10px 10px 10px 16px;
          position: fixed;
          right: 16px;
          top: 16px;
          z-index: 2147483647;
        }
        .label { color: #c9c5b9; font-size: 12px; font-weight: 500; }
        .timer {
          color: #ffcf70;
          font-variant-numeric: tabular-nums;
          font-size: 19px;
          min-width: 46px;
        }
        button {
          appearance: none;
          background: #ffcf70;
          border: 0;
          border-radius: 9px;
          color: #181713;
          cursor: pointer;
          font: inherit;
          padding: 9px 12px;
        }
        button:disabled { cursor: wait; opacity: .65; }
        .message { color: #ffaaa0; font-size: 12px; max-width: 190px; }
        .message:empty { display: none; }
      </style>
      <section class="card" role="timer" aria-live="assertive" aria-label="Break ending">
        <span class="label">Break ending</span>
        <strong class="timer">00:10</strong>
        <button type="button">+30 sec</button>
        <span class="message"></span>
      </section>
    `;
    countdown = shadow.querySelector(".timer");
    extensionButton = shadow.querySelector("button");
    message = shadow.querySelector(".message");
    extensionButton.addEventListener("click", extendBreak);
    (document.documentElement || document.body).appendChild(root);
  }

  function showOverlay() {
    createOverlay();
    root.style.setProperty("display", "block", "important");
  }

  function hideOverlay() {
    if (root) {
      root.style.setProperty("display", "none", "important");
    }
  }

  function scheduleRender(delayMilliseconds) {
    if (renderTimerId !== null) {
      window.clearTimeout(renderTimerId);
    }
    renderTimerId = window.setTimeout(
      render,
      Math.max(50, delayMilliseconds),
    );
  }

  async function extendBreak() {
    if (!extensionButton) {
      return;
    }
    extensionButton.disabled = true;
    message.textContent = "";
    try {
      const response = await chrome.runtime.sendMessage({
        type: "extendBreak",
      });
      if (!response?.ok) {
        throw new Error(response?.error || "Could not extend this break.");
      }
      sessionState = response.state;
      expiryHandledFor = null;
      render();
    } catch (error) {
      message.textContent =
        error instanceof Error ? error.message : "Could not extend this break.";
    } finally {
      extensionButton.disabled = false;
    }
  }

  function render() {
    if (renderTimerId !== null) {
      window.clearTimeout(renderTimerId);
      renderTimerId = null;
    }
    const now = Date.now();
    if (
      sessionState?.active &&
      sessionState.phase !== "break" &&
      enforceRestrictedPage(sessionState)
    ) {
      hideOverlay();
      return;
    }
    if (
      !sessionState?.active ||
      sessionState.phase !== "break" ||
      !currentPageIsRestricted(sessionState)
    ) {
      hideOverlay();
      return;
    }

    const deadline = Math.min(
      Number(sessionState.breakEndAt),
      Number(sessionState.endAt),
    );
    const remaining = deadline - now;
    if (!Number.isFinite(remaining)) {
      hideOverlay();
      return;
    }
    if (remaining > FINAL_SECONDS * 1000) {
      hideOverlay();
      // Stay dormant until the shot-clock window. State-change messages reset
      // this deadline if the native app changes or extends the break. Recheck
      // periodically because highly dynamic sites can detach injected nodes,
      // and browsers may delay a single long-running page timer.
      scheduleRender(
        Math.min(1000, remaining - FINAL_SECONDS * 1000),
      );
      return;
    }

    if (remaining <= 0) {
      hideOverlay();
      if (expiryHandledFor !== deadline) {
        expiryHandledFor = deadline;
        void chrome.runtime.sendMessage({ type: "enforceNow" });
      }
      return;
    }

    showOverlay();
    const seconds = Math.max(1, Math.ceil(remaining / 1000));
    countdown.textContent = `00:${String(seconds).padStart(2, "0")}`;
    extensionButton.hidden =
      Number(sessionState.breakEndAt) >= Number(sessionState.endAt);
    scheduleRender(Math.min(250, remaining));
  }

  chrome.runtime.onMessage.addListener((incoming) => {
    if (incoming?.type === "stateChanged") {
      sessionState = incoming.state;
      expiryHandledFor = null;
      render();
    }
  });

  chrome.storage.local
    .get("cachedSessionState")
    .then((stored) => {
      if (stored.cachedSessionState) {
        sessionState = stored.cachedSessionState;
        render();
      }
    })
    .catch(() => {
      // DNR enforcement does not depend on the content script.
    });

  chrome.storage.onChanged.addListener((changes, areaName) => {
    if (
      areaName === "local" &&
      changes.cachedSessionState?.newValue
    ) {
      sessionState = changes.cachedSessionState.newValue;
      expiryHandledFor = null;
      render();
    }
  });

  window.addEventListener(
    "pagehide",
    () => {
      if (renderTimerId !== null) {
        window.clearTimeout(renderTimerId);
      }
    },
    { once: true },
  );
})();
