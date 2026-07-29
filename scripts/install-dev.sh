#!/bin/zsh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 "FocusSession can only be installed on macOS."
  exit 1
fi

if (( $# == 0 )) || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  print -u2 "Usage: $0 <chrome-or-brave-extension-id> [additional-extension-id ...]"
  print -u2 "Load BrowserExtension as an unpacked extension, then copy its 32-letter ID."
  (( $# == 0 )) && exit 1
  exit 0
fi

if ! command -v swift >/dev/null 2>&1; then
  print -u2 "Swift is unavailable. Install Xcode 15.3 or later and select its command-line tools."
  print -u2 "Run ./scripts/doctor.sh for the complete setup check."
  exit 1
fi

extension_id_pattern='^[a-p]{32}$'
for extension_id in "$@"; do
  if [[ ! "$extension_id" =~ $extension_id_pattern ]]; then
    print -u2 "Invalid Chromium extension ID: $extension_id"
    exit 1
  fi
done

script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
project_directory="$(dirname "$script_directory")"
package_directory="$project_directory/macOS"
application_directory="$HOME/Applications/FocusSession.app"
application_contents="$application_directory/Contents"
host_binary="$application_contents/MacOS/FocusSessionNativeHost"
host_name="com.focussession.nativehost"

print "Building FocusSession…"
swift build -c release --package-path "$package_directory" --product FocusSessionApp
swift build -c release --package-path "$package_directory" --product FocusSessionNativeHost

build_directory="$(swift build -c release --package-path "$package_directory" --show-bin-path)"

mkdir -p "$application_contents/MacOS" "$application_contents/Resources"
cp "$build_directory/FocusSessionApp" "$application_contents/MacOS/FocusSessionApp"

/usr/bin/plutil -create xml1 "$application_contents/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "FocusSession" "$application_contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string "FocusSessionApp" "$application_contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "com.focussession.app" "$application_contents/Info.plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$application_contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "FocusSession" "$application_contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$application_contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "0.1.0" "$application_contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "1" "$application_contents/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "14.0" "$application_contents/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool true "$application_contents/Info.plist"
/usr/bin/plutil -insert CFBundleURLTypes -json \
  '[{"CFBundleURLName":"com.focussession.app","CFBundleURLSchemes":["focussession"]}]' \
  "$application_contents/Info.plist"

cp "$build_directory/FocusSessionNativeHost" "$host_binary"
chmod 755 "$host_binary"

allowed_origins=""
for extension_id in "$@"; do
  if [[ -n "$allowed_origins" ]]; then
    allowed_origins+=", "
  fi
  allowed_origins+="\"chrome-extension://$extension_id/\""
done

host_manifest="$(mktemp)"
trap '/bin/rm -f -- "$host_manifest"' EXIT
{
  print "{"
  print "  \"name\": \"$host_name\","
  print "  \"description\": \"FocusSession local browser bridge\","
  print "  \"path\": \"$host_binary\","
  print "  \"type\": \"stdio\","
  print "  \"allowed_origins\": [$allowed_origins]"
  print "}"
} > "$host_manifest"

chrome_hosts="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
brave_hosts="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"

mkdir -p "$chrome_hosts" "$brave_hosts"
cp "$host_manifest" "$chrome_hosts/$host_name.json"
cp "$host_manifest" "$brave_hosts/$host_name.json"
chmod 600 \
  "$chrome_hosts/$host_name.json" \
  "$brave_hosts/$host_name.json"
/bin/rm -f -- "$host_manifest"
trap - EXIT

/usr/bin/codesign --force --deep --sign - "$application_directory"

print ""
print "Installed:"
print "  $application_directory"
print "  $host_binary"
print "  Chrome and Brave native-messaging manifests"
print ""
print "Quit and reopen Chrome/Brave once, then open FocusSession."
if [[ "${FOCUSSESSION_SKIP_OPEN:-0}" != "1" ]]; then
  open "$application_directory"
fi
