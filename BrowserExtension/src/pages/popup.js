import {
  deriveSessionState,
  sessionStatus,
} from "../shared/state.js";

const statusElement = document.querySelector("#status");
const detailElement = document.querySelector("#detail");
const nativeElement = document.querySelector("#native-status");
const errorElement = document.querySelector("#error");
const breakButton = document.querySelector("#start-break");
const optionsButton = document.querySelector("#options");

let currentState = null;
let currentNativeStatus = null;

function duration(milliseconds) {
  const seconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  return hours > 0
    ? `${hours}h ${minutes}m`
    : `${minutes}:${String(remainder).padStart(2, "0")}`;
}

function render(response) {
  const now = Date.now();
  currentState = deriveSessionState(response.state, now);
  currentNativeStatus = response.nativeStatus ?? currentNativeStatus;
  const status = sessionStatus(currentState, now);
  breakButton.hidden = status !== "break-available";

  if (status === "inactive") {
    statusElement.textContent = "No active session";
    detailElement.textContent = "Start one from the Focus Session menu-bar app.";
  } else if (status === "break") {
    statusElement.textContent = "Free-use break";
    detailElement.textContent = `${duration(
      Math.min(currentState.breakEndAt, currentState.endAt) - now,
    )} remaining`;
  } else if (status === "break-available") {
    statusElement.textContent = "Break ready";
    detailElement.textContent = "Claim it whenever you want. Breaks do not stack.";
  } else {
    statusElement.textContent = "Focusing";
    detailElement.textContent =
      currentState.breakDurationSeconds === 0
        ? `Session ends in ${duration(currentState.endAt - now)}`
        : `Break in ${duration(
            currentState.nextBreakAvailableAt - now,
          )}`;
  }

  nativeElement.textContent = currentNativeStatus?.connected
    ? "Mac app connected"
    : "Using cached state";
  nativeElement.dataset.connected = String(
    currentNativeStatus?.connected === true,
  );
}

async function refresh(type = "getState") {
  const response = await chrome.runtime.sendMessage({ type });
  if (!response?.ok) {
    throw new Error(response?.error || "Could not read the session.");
  }
  render(response);
}

breakButton.addEventListener("click", async () => {
  breakButton.disabled = true;
  errorElement.textContent = "";
  try {
    await refresh("startBreak");
  } catch (error) {
    errorElement.textContent =
      error instanceof Error ? error.message : "Could not start the break.";
  } finally {
    breakButton.disabled = false;
  }
});

optionsButton.addEventListener("click", () => {
  void chrome.runtime.sendMessage({ type: "openOptions" });
});

refresh("refreshState").catch((error) => {
  errorElement.textContent =
    error instanceof Error ? error.message : "Could not read the session.";
});
window.setInterval(() => {
  if (currentState) {
    render({ state: currentState, nativeStatus: currentNativeStatus });
  }
}, 1000);
