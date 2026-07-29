#!/usr/bin/env bash

set -euo pipefail

failures=0
warnings=0

pass() {
    printf 'PASS  %s\n' "$1"
}

fail() {
    printf 'FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

warn() {
    printf 'WARN  %s\n' "$1"
    warnings=$((warnings + 1))
}

if [[ "$(uname -s)" == "Darwin" ]]; then
    pass "macOS detected"
else
    fail "FocusSession can only be installed on macOS."
fi

if command -v sw_vers >/dev/null 2>&1; then
    macos_major="$(sw_vers -productVersion | cut -d. -f1)"
    if [[ "$macos_major" =~ ^[0-9]+$ ]] && (( macos_major >= 14 )); then
        pass "macOS 14 or later"
    else
        fail "macOS 14 or later is required."
    fi
fi

if command -v swift >/dev/null 2>&1; then
    pass "Swift is available"
else
    fail "Swift is missing. Install Xcode 15.3 or later, then select its command-line tools."
fi

if command -v xcode-select >/dev/null 2>&1 \
    && xcode-select -p >/dev/null 2>&1; then
    pass "Xcode command-line tools are selected"
else
    fail "Xcode command-line tools are not selected. Run: xcode-select --install"
fi

if [[ -d "/Applications/Google Chrome.app" ]] \
    || [[ -d "/Applications/Brave Browser.app" ]]; then
    pass "Chrome or Brave is installed"
else
    fail "Install Google Chrome or Brave to use website blocking."
fi

if command -v node >/dev/null 2>&1; then
    node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
    if (( node_major >= 20 )); then
        pass "Node.js 20 or later (needed for verification)"
    else
        warn "Node.js is older than 20. Installation can continue, but the browser tests cannot."
    fi
else
    warn "Node.js is not installed. Installation can continue, but verification requires Node.js 20 or later."
fi

if (( failures > 0 )); then
    printf '\n%d required check(s) failed; fix them before installing.\n' "$failures"
    exit 1
fi

if (( warnings > 0 )); then
    printf '\nRequired setup is ready, with %d optional warning(s).\n' "$warnings"
else
    printf '\nFocusSession development setup is ready.\n'
fi
