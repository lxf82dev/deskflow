#!/bin/zsh
# SPDX-FileCopyrightText: (C) 2026 lxf82dev <lxf82dev@gmail.com>
# SPDX-License-Identifier: GPL-2.0-only WITH LicenseRef-OpenSSL-Exception

set -eu
umask 077
session_dir="$HOME/Library/Application Support/DeskflowForkTest"
login_state="$session_dir/login-backup"
app="$HOME/Applications/Deskflow Fork Test.app"
if [[ -d "$HOME/Applications/Fork.app" ]]; then app="$HOME/Applications/Fork.app"; fi
if [[ -d "$HOME/Applications/Deskflow+.app" ]]; then app="$HOME/Applications/Deskflow+.app"; fi
agent="$HOME/Library/LaunchAgents/local.deskflow.fork-login.plist"
domain="gui/$(id -u)"
target="$domain/local.deskflow.fork-login"
fail() { print -u2 -- "$*"; exit 1; }
(( EUID != 0 )) || fail 'Run as your desktop user, without sudo.'

check_login() {
  [[ "$app" == "$HOME/Applications/Deskflow+.app" && -f "$app/Contents/MacOS/Deskflow" ]] || fail 'Deskflow+ is missing. Finish the renamed app cleanup first.'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" == dev.lxf82.deskflow.forktest ]] || fail 'Unexpected Deskflow+ app identifier.'
  /usr/bin/codesign --verify --deep --strict "$app"
  [[ -f "$login_state/installed" && -f "$agent" ]] || fail 'The permanent login entry is missing. Run this script with install first.'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print Label' "$agent")" == local.deskflow.fork-login &&
     "$(/usr/libexec/PlistBuddy -c 'Print ProgramArguments:0' "$agent")" == /usr/bin/open &&
     "$(/usr/libexec/PlistBuddy -c 'Print ProgramArguments:1' "$agent")" == -g &&
     "$(/usr/libexec/PlistBuddy -c 'Print ProgramArguments:2' "$agent")" == "$app" &&
     "$(/usr/libexec/PlistBuddy -c 'Print RunAtLoad' "$agent")" == true &&
     "$(/usr/libexec/PlistBuddy -c 'Print LimitLoadToSessionType' "$agent")" == Aqua ]] || fail 'The login entry does not match the expected Deskflow+ configuration.'
  /bin/launchctl print "$target" >/dev/null 2>&1 || fail 'The Deskflow+ login entry is not loaded. Run this script with install first.'
  /bin/launchctl print-disabled "$domain" | /usr/bin/awk '$1=="\"local.deskflow.fork-login\"" && $2=="=>" && ($3=="disabled" || $3=="true") {exit 1}' || fail 'The Deskflow+ login entry is disabled. Run this script with install first.'
  /usr/bin/awk '/^\[gui\]/{s=1;next} /^\[/{s=0} s && /^startCoreWithGui=true$/{found=1} END{exit !found}' "$HOME/Library/Deskflow/Deskflow.conf" || fail 'Deskflow input sharing is not configured to start with its GUI.'
  /usr/bin/awk '/^\[core\]/{s=1;next} /^\[/{s=0} s && /^processMode=1$/{found=1} END{exit !found}' "$HOME/Library/Deskflow/Deskflow.conf" || fail 'Deskflow is not configured for desktop process mode.'
  print -- "LOGIN OK: Deskflow+ is enabled at login for $(id -un); input sharing starts with it."
  print -- 'This checks the saved configuration and loaded login job; a real logout/reboot remains the final startup test.'
}

restore_retired_helpers() {
  for name in 'Deskflow MX Relay' 'Deskflow Smooth Mode'; do
    archived="$session_dir/retired-helpers/apps/$name.app"
    if [[ -d "$archived" && ! -e "$HOME/Applications/$name.app" ]]; then
      /usr/bin/ditto "$archived" "$HOME/Applications/$name.app"
    fi
  done
  for label in local.deskflow.mx-middle-relay local.deskflow.mx-awdl-menu; do
    archived="$session_dir/retired-helpers/agents/$label.plist"
    if [[ -f "$archived" && ! -e "$HOME/Library/LaunchAgents/$label.plist" ]]; then
      /bin/cp "$archived" "$HOME/Library/LaunchAgents/$label.plist"
    fi
  done
}

stop_user_deskflow() {
  /usr/bin/pkill -TERM -u "$(id -u)" -x Deskflow 2>/dev/null || true
  /usr/bin/pkill -TERM -u "$(id -u)" -x deskflow-core 2>/dev/null || true
  for attempt in {1..50}; do
    if ! /usr/bin/pgrep -u "$(id -u)" -x Deskflow >/dev/null &&
       ! /usr/bin/pgrep -u "$(id -u)" -x deskflow-core >/dev/null; then return; fi
    /bin/sleep 0.1
  done
  fail 'Deskflow did not stop. Close it and retry; no forced kill was used.'
}

undo_login() {
  [[ -f "$login_state/legacy.before" ]] || fail 'No permanent login recovery record exists.'
  if /bin/launchctl print "$target" >/dev/null 2>&1; then
    /bin/launchctl bootout "$target"
  fi
  if [[ -f "$agent" ]]; then
    /bin/cp "$agent" "$login_state/removed-fork-login.plist"
    /bin/rm "$agent"
  fi
  while read -r label previous; do
    case "$label" in
      local.deskflow.mx-middle-relay|local.deskflow.mx-awdl-menu)
        if [[ "$previous" == disabled ]]; then /bin/launchctl disable "$domain/$label";
        else /bin/launchctl enable "$domain/$label"; fi
        ;;
    esac
  done < "$login_state/legacy.before"
  /bin/rm -f "$login_state/installed"

}

if [[ "${1:-}" == install ]]; then
  [[ -f "$session_dir/active" ]] || fail 'Complete the two-Mac fork test before making it permanent.'
  [[ -f "$app/Contents/MacOS/Deskflow" ]] || fail 'The tested fork app is missing.'
  app_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")"
  [[ "$app_id" == dev.lxf82.deskflow.forktest ]] || fail 'The installed app is not the tested fork.'
  /usr/bin/codesign --verify --deep --strict "$app"
  /usr/bin/awk '/^\[gui\]/{s=1;next} /^\[/{s=0} s && /^startCoreWithGui=false$/{exit 1}' "$HOME/Library/Deskflow/Deskflow.conf" || fail 'Start Deskflow input sharing from its menu, then retry so the core will also start at login.'
  /bin/mkdir -p "$HOME/Library/LaunchAgents" "$session_dir"
  /bin/chmod 700 "$session_dir"
  if [[ ! -d "$login_state" ]]; then
    [[ ! -e "$agent" ]] || fail 'A fork login entry already exists without a recovery record; refusing replacement.'
    /bin/mkdir "$login_state"
    /bin/launchctl print-disabled "$domain" > "$login_state/disabled.before.txt"
    : > "$login_state/legacy.before"
    for label in local.deskflow.mx-middle-relay local.deskflow.mx-awdl-menu; do
      if [[ -f "$HOME/Library/LaunchAgents/$label.plist" ]]; then
        previous="$(/usr/bin/awk -v key="\"$label\"" '$1==key && $2=="=>" { if ($3=="disabled" || $3=="true") print "disabled"; else print "enabled"; found=1 } END {if(!found)print "enabled"}' "$login_state/disabled.before.txt")"
        print -r -- "$label $previous" >> "$login_state/legacy.before"
      fi
    done
  fi
  [[ -f "$login_state/legacy.before" ]] || fail 'The login recovery record is incomplete.'
  temp_agent="$(/usr/bin/mktemp "$session_dir/login-agent.XXXXXX")"
  trap '/bin/rm -f "$temp_agent"' EXIT
  /usr/bin/plutil -create xml1 "$temp_agent"
  /usr/bin/plutil -insert Label -string local.deskflow.fork-login "$temp_agent"
  /usr/bin/plutil -insert ProgramArguments -array "$temp_agent"
  /usr/bin/plutil -insert ProgramArguments.0 -string /usr/bin/open "$temp_agent"
  /usr/bin/plutil -insert ProgramArguments.1 -string -g "$temp_agent"
  /usr/bin/plutil -insert ProgramArguments.2 -string "$app" "$temp_agent"
  /usr/bin/plutil -insert RunAtLoad -bool YES "$temp_agent"
  /usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$temp_agent"
  /usr/bin/plutil -insert StandardOutPath -string "$session_dir/login.log" "$temp_agent"
  /usr/bin/plutil -insert StandardErrorPath -string "$session_dir/login.log" "$temp_agent"
  /usr/bin/plutil -lint "$temp_agent"
  /bin/chmod 644 "$temp_agent"
  /bin/cp "$temp_agent" "$agent"
  while read -r label previous; do
    case "$label" in
      local.deskflow.mx-middle-relay|local.deskflow.mx-awdl-menu)
        /bin/launchctl disable "$domain/$label"
        if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
          /bin/launchctl bootout "$domain/$label"
        fi
        ;;
    esac
  done < "$login_state/legacy.before"
  /usr/bin/pkill -TERM -u "$(id -u)" -x mx-middle-relay 2>/dev/null || true
  /usr/bin/pkill -TERM -u "$(id -u)" -x SmoothMenu 2>/dev/null || true
  /bin/launchctl enable "$target"
  if /bin/launchctl print "$target" >/dev/null 2>&1; then
    /bin/launchctl bootout "$target"
  fi
  /bin/launchctl bootstrap "$domain" "$agent"
  : > "$login_state/installed"
  if [[ "${0:A}" != "$session_dir/permanent-login.zsh" ]]; then
    /bin/cp "${0:A}" "$session_dir/permanent-login.zsh"
    /bin/chmod 700 "$session_dir/permanent-login.zsh"
  fi
  print -- 'Permanent fork login enabled. Old relay/DF menu login agents disabled.'
  print -- 'The running fork, its permissions, and the AWDL background worker were preserved.'
  print -- 'Check System Settings → General → Login Items: remove the ORIGINAL Deskflow from Open at Login if it is listed. Keep the AWDL worker allowed.'
  print -- 'Undo only this login change: /bin/zsh "$HOME/Library/Application Support/DeskflowForkTest/permanent-login.zsh" undo'
  print -- 'Restore the full original setup: /bin/zsh "$HOME/Library/Application Support/DeskflowForkTest/permanent-login.zsh" restore'
elif [[ "${1:-}" == cleanup ]]; then
  [[ -f "$login_state/installed" && -f "$session_dir/active" ]] || fail 'Finish the tested permanent login setup before cleanup.'
  old_app="$app"
  new_app="$HOME/Applications/Deskflow+.app"
  [[ "$old_app" == "$new_app" || ! -e "$new_app" ]] || fail 'Both old and new app paths exist. Nothing will be overwritten.'
  [[ -d "$app" ]] || fail 'The working fork app is missing.'
  app_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")"
  [[ "$app_id" == dev.lxf82.deskflow.forktest ]] || fail 'The destination is not this fork; refusing replacement.'
  /usr/bin/codesign --verify --deep --strict "$app"
  # Validate all retirement targets before moving any of them.
  for name expected in 'Deskflow MX Relay' local.deskflow.mx-middle-relay 'Deskflow Smooth Mode' local.deskflow.mx-smooth-mode; do
    if [[ -e "$HOME/Applications/$name.app" ]]; then
      actual="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$HOME/Applications/$name.app/Contents/Info.plist")"
      [[ "$actual" == "$expected" ]] || fail "Unrelated app at $name; nothing has been removed."
      [[ ! -e "$session_dir/retired-helpers/apps/$name.app" ]] || fail "An archive already exists for $name; nothing will be overwritten."
    fi
  done
  for label in local.deskflow.mx-middle-relay local.deskflow.mx-awdl-menu; do
    if [[ -e "$HOME/Library/LaunchAgents/$label.plist" ]]; then
      actual="$(/usr/libexec/PlistBuddy -c 'Print Label' "$HOME/Library/LaunchAgents/$label.plist")"
      [[ "$actual" == "$label" ]] || fail 'Unexpected startup entry; refusing removal.'
      [[ ! -e "$session_dir/retired-helpers/agents/$label.plist" ]] || fail 'A startup-entry archive already exists; nothing will be overwritten.'
    fi
  done
  /bin/mkdir -p "$session_dir/retired-helpers/apps" "$session_dir/retired-helpers/agents" "$session_dir/cleanup-backup"
  if [[ "${0:A}" != "$session_dir/permanent-login.zsh" ]]; then
    /bin/cp "${0:A}" "$session_dir/permanent-login.zsh"
    /bin/chmod 700 "$session_dir/permanent-login.zsh"
  fi
  if [[ "$old_app" != "$new_app" ]]; then
    staged="$session_dir/cleanup-backup/Deskflow+.staging.app"
    original_backup="$session_dir/cleanup-backup/${old_app:t}"
    [[ ! -e "$staged" && ! -e "$original_backup" ]] || fail 'An earlier rename backup exists; refusing overwrite.'
    /usr/bin/ditto "$old_app" "$staged"
    /usr/bin/plutil -replace CFBundleName -string Deskflow+ "$staged/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleDisplayName -string Deskflow+ "$staged/Contents/Info.plist"
    /usr/bin/codesign --force --deep --sign - "$staged"
    /usr/bin/codesign --verify --deep --strict "$staged"
  fi
  for label in local.deskflow.mx-middle-relay local.deskflow.mx-awdl-menu; do
    /bin/launchctl disable "$domain/$label"
    if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then /bin/launchctl bootout "$domain/$label"; fi
    if [[ -f "$HOME/Library/LaunchAgents/$label.plist" ]]; then
      /bin/mv "$HOME/Library/LaunchAgents/$label.plist" "$session_dir/retired-helpers/agents/$label.plist"
    fi
  done
  /usr/bin/pkill -TERM -u "$(id -u)" -x mx-middle-relay 2>/dev/null || true
  /usr/bin/pkill -TERM -u "$(id -u)" -x SmoothMenu 2>/dev/null || true
  for name in 'Deskflow MX Relay' 'Deskflow Smooth Mode'; do
    if [[ -d "$HOME/Applications/$name.app" ]]; then
      /bin/mv "$HOME/Applications/$name.app" "$session_dir/retired-helpers/apps/$name.app"
    fi
  done
  if [[ "$old_app" != "$new_app" ]]; then
    if /bin/launchctl print "$target" >/dev/null 2>&1; then /bin/launchctl bootout "$target"; fi
    stop_user_deskflow
    /bin/mv "$old_app" "$original_backup"
    /bin/mv "$staged" "$new_app"
  fi
  /bin/zsh "${0:A}" install
  : > "$session_dir/cleanup-backup/completed"
  print -- 'Cleanup complete: Deskflow+.app is the working app; retired helper apps and startup files are archived privately.'
  print -- 'The AWDL worker and current Deskflow settings were retained. If macOS requests it after the display-name/signature change, re-enable Deskflow+ in Accessibility.'
elif [[ "${1:-}" == status ]]; then
  check_login
elif [[ "${1:-}" == retire-original ]]; then
  check_login
  original=/Applications/Deskflow.app
  archived="$session_dir/retired-original/Deskflow.app"
  if [[ -e "$original" ]]; then
    [[ ! -L "$original" && -d "$original" ]] || fail 'The original app path is unexpected; nothing has been moved.'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$original/Contents/Info.plist")" == org.deskflow.deskflow ]] || fail 'The original app path contains a different app; nothing has been moved.'
    [[ ! -e "$archived" ]] || fail 'An original-app archive already exists; refusing overwrite.'
    if /usr/bin/pgrep -f '^/Applications/Deskflow[.]app/Contents/MacOS/(Deskflow|deskflow-core)( |$)' >/dev/null; then
      fail 'The original Deskflow is still running. Quit only that app, keeping Deskflow+ open, then retry.'
    fi
    /bin/mkdir -p "$session_dir/retired-original"
    # Keep recovery aware of the archived original before changing its location.
    if [[ "${0:A}" != "$session_dir/permanent-login.zsh" ]]; then
      /bin/cp "${0:A}" "$session_dir/permanent-login.zsh"
      /bin/chmod 700 "$session_dir/permanent-login.zsh"
    fi
    /bin/mv "$original" "$archived" || fail 'macOS denied moving the original app. Move /Applications/Deskflow.app to Trash in Finder, then rerun status. Deskflow+ was not stopped.'
    print -- 'Original Deskflow removed from Applications and archived privately for recovery.'
  elif [[ -d "$archived" ]]; then
    print -- 'Original Deskflow is already archived; no change needed.'
  else
    print -- 'Original Deskflow is absent from Applications; no change needed.'
  fi
  print -- 'Deskflow+, its login entry, shared settings and the privileged AWDL worker were retained.'
elif [[ "${1:-}" == undo ]]; then
  undo_login
  print -- 'Fork login removed and prior helper enable/disable settings restored. Running apps were not stopped.'
elif [[ "${1:-}" == restore ]]; then
  [[ -f "$session_dir/active" ]] || fail 'No original setup backup was found.'
  backup="$(<"$session_dir/active")"
  [[ "$backup" == "$session_dir"/backup-* && -d "$backup/Deskflow" ]] || fail 'The original setup backup is missing or invalid.'
  original=/Applications/Deskflow.app
  if [[ ! -d "$original" ]]; then
    original="$session_dir/retired-original/Deskflow.app"
    [[ -d "$original" && "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$original/Contents/Info.plist")" == org.deskflow.deskflow ]] || fail 'The original app is missing; reinstall official Deskflow before restoring. The working fork has not been stopped.'
  fi
  restore_retired_helpers
  if [[ -f "$login_state/installed" ]]; then undo_login; fi
  stop_user_deskflow
  /bin/mv "$HOME/Library/Deskflow" "$backup/Deskflow.after-permanent-$(date +%Y%m%d-%H%M%S)"
  /usr/bin/ditto "$backup/Deskflow" "$HOME/Library/Deskflow"
  /bin/cp "$backup/control" "$HOME/Library/Application Support/DeskflowMXAWDL/control"
  while IFS= read -r label; do
    case "$label" in
      local.deskflow.mx-middle-relay|local.deskflow.mx-awdl-menu)
        if ! /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
          /bin/launchctl bootstrap "$domain" "$HOME/Library/LaunchAgents/$label.plist"
        fi
        ;;
    esac
  done < "$backup/loaded-agents"
  /usr/bin/open "$original"
  /bin/rm "$session_dir/active"
  print -- 'Original Deskflow, its settings and the previously running helpers restored. Private backups retained.'
else
  fail 'Usage: permanent-login.zsh install|cleanup|status|retire-original|undo|restore'
fi
