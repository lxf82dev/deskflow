#!/bin/zsh
# SPDX-FileCopyrightText: (C) 2026 lxf82dev <lxf82dev@gmail.com>
# SPDX-License-Identifier: GPL-2.0-only WITH LicenseRef-OpenSSL-Exception

set -eu
umask 077
session_dir="$HOME/Library/Application Support/DeskflowForkTest"
official_app="/Applications/Deskflow.app"
test_app="$HOME/Applications/Deskflow Fork Test.app"
prefs_dir="$HOME/Library/Deskflow"
control="$HOME/Library/Application Support/DeskflowMXAWDL/control"
domain="gui/$(id -u)"
package_dir="${0:A:h}"

fail() { print -u2 -- "$*"; exit 1; }
(( EUID != 0 )) || fail 'Run this test command as your desktop user, without sudo.'
stop_deskflow() {
  /usr/bin/pkill -TERM -u "$(id -u)" -x Deskflow 2>/dev/null || true
  /usr/bin/pkill -TERM -u "$(id -u)" -x deskflow-core 2>/dev/null || true
  for attempt in {1..50}; do
    if ! /usr/bin/pgrep -u "$(id -u)" -x Deskflow >/dev/null &&
       ! /usr/bin/pgrep -u "$(id -u)" -x deskflow-core >/dev/null; then return; fi
    /bin/sleep 0.1
  done
  fail 'Deskflow did not stop. Close it and retry. No forced kill was used.'
}

if [[ "${1:-}" == start ]]; then
  [[ ! -d "$HOME/Applications/Deskflow+.app" ]] || fail 'Deskflow+ is already installed. Reopen it or use the private permanent-login.zsh restore command before starting a new test.'
  [[ "$(uname -m)" == arm64 ]] || fail 'This package is for Apple Silicon.'
  os_version="$(sw_vers -productVersion)"
  (( ${os_version%%.*} >= 27 )) || fail 'This test package requires macOS 27 or newer.'
  [[ -d "$official_app" && -f "$prefs_dir/Deskflow.conf" ]] || fail 'The existing Deskflow app and user settings are required.'
  [[ -f "$control" && -f /Library/LaunchDaemons/local.deskflow.mx-awdl.plist ]] || fail 'Install Smooth Mode first. This test reuses the existing worker.'
  /usr/bin/awk '/^\[core\]/{s=1;next} /^\[/{s=0} s && /^processMode=0$/{exit 1}' "$prefs_dir/Deskflow.conf" || fail 'Switch Deskflow to desktop process mode before this test.'
  [[ ! -e "$session_dir/active" ]] || fail 'A test session already exists. Reopen the test app, or run Restore Previous Setup.command first.'
  /usr/bin/codesign --verify --deep --strict "$package_dir/Deskflow Fork Test.app"
  /bin/mkdir -p "$session_dir" "$HOME/Applications"
  /bin/chmod 700 "$session_dir"
  if [[ -e "$test_app" ]]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$test_app/Contents/Info.plist")"
    [[ "$existing_id" == dev.lxf82.deskflow.forktest ]] || fail 'An unrelated app occupies the test app path.'
    /bin/mv "$test_app" "$session_dir/previous-test-app-$(date +%Y%m%d-%H%M%S).app"
  fi
  /usr/bin/ditto "$package_dir/Deskflow Fork Test.app" "$test_app"
  /usr/bin/xattr -dr com.apple.quarantine "$test_app" 2>/dev/null || true
  /usr/bin/codesign --verify --deep --strict "$test_app"
  backup="$session_dir/backup-$(date +%Y%m%d-%H%M%S)"
  /bin/mkdir "$backup"
  # Stop only this user's desktop processes, then snapshot persisted preferences.
  # The administrator-owned AWDL worker continues running throughout the test.
  stop_deskflow
  /usr/bin/ditto "$prefs_dir" "$backup/Deskflow"
  /bin/cp "$control" "$backup/control"
  : > "$backup/loaded-agents"
  print -r -- "$backup" > "$session_dir/active"
  for label in local.deskflow.mx-middle-relay local.deskflow.mx-awdl-menu; do
    if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
      print -r -- "$label" >> "$backup/loaded-agents"
      /bin/launchctl bootout "$domain/$label"
    fi
  done
  /usr/bin/open "$test_app"
  print -- 'Fork test started. Grant Accessibility to Deskflow Fork Test if requested.'
  print -- 'In the SERVER fork, enable Logi Options+ input compatibility and navigation gesture forwarding under Configure Server → Advanced.'
  print -- 'Keep the existing Shift+Tab hotkey, cursor lock, protocol and file logging.'
  print -- 'The old helper login entries are only unloaded for this login session. Do not log out during the first test.'
  print -r -- "Rollback: /bin/zsh '$package_dir/Restore Previous Setup.command'"
elif [[ "${1:-}" == restore ]]; then
  if [[ -f "$session_dir/cleanup-backup/completed" && -f "$session_dir/permanent-login.zsh" ]]; then
    exec /bin/zsh "$session_dir/permanent-login.zsh" restore
  fi
  [[ -f "$session_dir/active" ]] || fail 'No active fork test backup was found.'
  backup="$(<"$session_dir/active")"
  [[ "$backup" == "$session_dir"/backup-* && -d "$backup/Deskflow" ]] || fail 'The test backup is missing or invalid.'
  if [[ -f "$session_dir/login-backup/installed" ]]; then
    [[ -f "$package_dir/permanent-login.zsh" ]] || fail 'Use the updated recovery package containing permanent-login.zsh.'
    /bin/zsh "$package_dir/permanent-login.zsh" undo
  fi
  stop_deskflow
  /bin/mv "$prefs_dir" "$backup/Deskflow.after-test-$(date +%Y%m%d-%H%M%S)"
  /usr/bin/ditto "$backup/Deskflow" "$prefs_dir"
  /bin/cp "$backup/control" "$control"
  while IFS= read -r label; do
    case "$label" in
      local.deskflow.mx-middle-relay|local.deskflow.mx-awdl-menu)
        if ! /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
          /bin/launchctl bootstrap "$domain" "$HOME/Library/LaunchAgents/$label.plist"
        fi
        ;;
    esac
  done < "$backup/loaded-agents"
  /usr/bin/open "$official_app"
  /bin/rm "$session_dir/active"
  print -- 'Previous Deskflow settings and the previously running helper agents restored.'
  print -r -- "Test settings and private backups remain in: $backup"
else
  fail 'Usage: test-session.zsh start|restore'
fi
