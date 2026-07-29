#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
project_directory="$(dirname "$script_directory")"

if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' "Node.js 20 or later is required. Run ./scripts/doctor.sh for setup help." >&2
  exit 1
fi

node -e '
  const major = Number(process.versions.node.split(".")[0]);
  if (!Number.isInteger(major) || major < 20) {
    console.error("Node.js 20 or later is required.");
    process.exit(1);
  }
'

node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
  "$project_directory/BrowserExtension/manifest.json"

bash -n \
  "$project_directory/scripts/doctor.sh" \
  "$project_directory/scripts/verify.sh"
if command -v zsh >/dev/null 2>&1; then
  zsh -n \
    "$project_directory/scripts/install-dev.sh" \
    "$project_directory/scripts/uninstall-dev.sh"
fi

npm --prefix "$project_directory/BrowserExtension" test
npm --prefix "$project_directory/BrowserExtension" run check

if [[ "$(uname -s)" == "Darwin" ]]; then
  if ! command -v swift >/dev/null 2>&1; then
    printf '%s\n' "Swift is required for verification on macOS. Run ./scripts/doctor.sh for setup help." >&2
    exit 1
  fi
  swift test --package-path "$project_directory/macOS"
else
  printf '%s\n' "Skipping Swift build: macOS with Xcode/Swift is required."
fi

printf '%s\n' "FocusSession verification complete."
