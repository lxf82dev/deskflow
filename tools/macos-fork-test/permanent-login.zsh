#!/bin/zsh
# SPDX-FileCopyrightText: (C) 2026 lxf82dev <lxf82dev@gmail.com>
# SPDX-License-Identifier: GPL-2.0-only WITH LicenseRef-OpenSSL-Exception

set -eu
umask 077
session_dir="$HOME/Library/Application Support/DeskflowForkTest"
login_state="$session_dir/login-backup"
app="$HOME/Applications/Deskflow Fork Test.app"
agent="$HOME/Library/LaunchAgents/local.deskflow.fork-login.plist"
domain="gui/$(id -u)"
target="$domain/local.deskflow.fork-login"
fail() { print -u2 -- "$*"; exit 1; }
(( EUID != 0 )) || fail 'Run as your desktop user, without sudo.'

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
elif [[ "${1:-}" == undo ]]; then
  undo_login
  print -- 'Fork login removed and prior helper enable/disable settings restored. Running apps were not stopped.'
elif [[ "${1:-}" == restore ]]; then
  [[ -f "$session_dir/active" ]] || fail 'No original setup backup was found.'
  backup="$(<"$session_dir/active")"
  [[ "$backup" == "$session_dir"/backup-* && -d "$backup/Deskflow" ]] || fail 'The original setup backup is missing or invalid.'
  if [[ -f "$login_state/installed" ]]; then undo_login; fi
  /usr/bin/pkill -TERM -u "$(id -u)" -x Deskflow 2>/dev/null || true
  /usr/bin/pkill -TERM -u "$(id -u)" -x deskflow-core 2>/dev/null || true
  for attempt in {1..50}; do
    if ! /usr/bin/pgrep -u "$(id -u)" -x Deskflow >/dev/null &&
       ! /usr/bin/pgrep -u "$(id -u)" -x deskflow-core >/dev/null; then break; fi
    /bin/sleep 0.1
  done
  if /usr/bin/pgrep -u "$(id -u)" -x Deskflow >/dev/null || /usr/bin/pgrep -u "$(id -u)" -x deskflow-core >/dev/null; then
    fail 'Deskflow did not stop. Close it and retry; settings have not been restored.'
  fi
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
  /usr/bin/open /Applications/Deskflow.app
  /bin/rm "$session_dir/active"
  print -- 'Original Deskflow, its settings and the previously running helpers restored. Private backups retained.'
else
  fail 'Usage: permanent-login.zsh install|undo|restore'
fi
