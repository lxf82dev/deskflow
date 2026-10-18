#!/bin/zsh
# SPDX-FileCopyrightText: (C) 2026 lxf82dev <lxf82dev@gmail.com>
# SPDX-License-Identifier: GPL-2.0-only WITH LicenseRef-OpenSSL-Exception

# Read-only audit: no service, app, permission or configuration changes.
set -u
session_dir="$HOME/Library/Application Support/DeskflowForkTest"
print -- '=== Deskflow+ login configuration ==='
if [[ -f "$session_dir/permanent-login.zsh" ]]; then
  /bin/zsh "$session_dir/permanent-login.zsh" status
else
  print -- 'Missing private login checker.'
fi
print -- '=== Installed apps, downloads and mounted installers (not private archives) ==='
for folder in /Applications "$HOME/Applications" "$HOME/Downloads" "$HOME/Desktop" /Volumes; do
  [[ -d "$folder" ]] || continue
  for item in "$folder"/*(N); do
    case "${item:t:l}" in
      *deskflow*|*mx-middle*|*smooth-mode*|*smooth\ mode*|fork.app) print -r -- "$item" ;;
    esac
  done
done
print -- '=== Deskflow startup files ==='
for folder in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons /Library/PrivilegedHelperTools; do
  [[ -d "$folder" ]] || continue
  for item in "$folder"/*(N); do
    case "${item:t:l}" in
      *deskflow*) print -r -- "$item" ;;
    esac
  done
done
print -- '=== Retired helper jobs (should be absent) ==='
for label in local.deskflow.mx-middle-relay local.deskflow.mx-awdl-menu; do
  if /bin/launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    print -- "UNEXPECTED loaded job: $label"
  else
    print -- "Absent: $label"
  fi
done
print -- '=== Running app/helper processes ==='
/bin/ps -axo pid=,comm= | /usr/bin/awk 'index($0,"Deskflow") || index($0,"deskflow-core") || index($0,"mx-middle-relay") || index($0,"SmoothMenu") || index($0,"local.deskflow.mx-awdl")'
print -- '=== AWDL worker status (retained intentionally) ==='
if [[ -r /Library/Logs/DeskflowMXAWDL/status ]]; then
  /bin/cat /Library/Logs/DeskflowMXAWDL/status
else
  print -- 'Worker status is unavailable.'
fi
print -- '=== Established Deskflow connections ==='
/usr/sbin/lsof -nP -iTCP:24800 -sTCP:ESTABLISHED || true
print -- '=== Private recovery archives (retained intentionally) ==='
for item in "$session_dir/cleanup-backup" "$session_dir/retired-helpers" "$session_dir/retired-original"; do
  [[ ! -d "$item" ]] || /usr/bin/du -sh "$item"
done
print -- 'Audit complete. This did not inspect or change macOS privacy grants; check those in System Settings.'
