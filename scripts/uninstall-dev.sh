#!/bin/zsh

set -euo pipefail

delete_data=0
if (( $# > 1 )); then
  print -u2 "Usage: $0 [--delete-data]"
  exit 2
fi
if (( $# == 1 )); then
  case "$1" in
    --delete-data)
      delete_data=1
      ;;
    --help|-h)
      print "Usage: $0 [--delete-data]"
      print "Without the flag, local settings and statistics are preserved."
      exit 0
      ;;
    *)
      print -u2 "Unknown option: $1"
      print -u2 "Usage: $0 [--delete-data]"
      exit 2
      ;;
  esac
fi

application_directory="$HOME/Applications/FocusSession.app"
support_directory="$HOME/Library/Application Support/FocusSession"
host_name="com.focussession.nativehost.json"
chrome_manifest="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/$host_name"
brave_manifest="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/$host_name"
application_executable="$application_directory/Contents/MacOS/FocusSessionApp"

if [[ -e "$application_directory" && ! -x "$application_executable" ]]; then
  print -u2 "FocusSession is installed, but its uninstaller entry point is missing."
  print -u2 "Reinstall this development build, then rerun the uninstall script."
  exit 1
fi

if [[ -x "$application_executable" ]]; then
  if ! "$application_executable" --unregister-login-item; then
    print -u2 "FocusSession could not remove its Launch at Login registration."
    print -u2 "Open FocusSession Settings, turn Launch at Login off, then rerun this script."
    exit 1
  fi
fi

/usr/bin/pkill -x FocusSessionApp 2>/dev/null || true

targets=(
  "$application_directory"
  "$support_directory/bin/FocusSessionNativeHost"
  "$chrome_manifest"
  "$brave_manifest"
)

for target in "${targets[@]}"; do
  if [[ -e "$target" ]]; then
    /bin/rm -rf -- "$target"
    print "Removed $target"
  fi
done

print ""
if (( delete_data == 1 )); then
  if [[ -e "$support_directory" ]]; then
    /bin/rm -rf -- "$support_directory"
    print "Removed local settings and statistics from $support_directory"
  fi
  print "Remove the unpacked browser extension separately to clear its per-profile cache."
else
  print "Local settings and statistics remain in $support_directory."
  print "Rerun with --delete-data only if you also want to erase that data."
fi
