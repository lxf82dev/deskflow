# Two-Mac fork test

This local Apple Silicon build requires **macOS 27.0 or newer**. It has an ad-hoc signature and is not Apple-notarized. It is intended for the two Macs where the existing Deskflow, MX Relay and Smooth Mode setup has already been configured.

The fork's Deskflow menu-bar dropdown now has **Smooth Mode** with worker status, Automatic smoothing, Allow AirDrop for 10 minutes, Resume automatic mode now, and the controller log. The background AWDL worker remains necessary for privileged interface changes; the separate DF menu app is no longer needed during this test. The mouse relay's input fixes run inside the fork.

## Start on both Macs

Keep another way to control the Mac mini available for initial macOS permission prompts. Copy/extract the whole package onto each Mac's local disk. Both Macs need the same fork version for protocol 1.9 navigation. Do not run this package's start command on only one Mac and expect the complete test to pass against the official build.

On each Mac, open Terminal in the extracted folder and run:

```sh
/bin/zsh "Start Fork Test.command"
```

Start the **client first**, then the server. The command:

1. Copies the signed app to `~/Applications/Deskflow Fork Test.app`, keeping `/Applications/Deskflow.app` intact.
2. Stops only this user's desktop Deskflow processes and privately backs up `~/Library/Deskflow` and the smoothing preference under `~/Library/Application Support/DeskflowForkTest/`.
3. Temporarily unloads the existing MX Relay and DF menu login agents if they are running. It retains their files and the root AWDL worker.
4. Opens the fork using the existing Deskflow settings, certificates, layout, hotkey, protocol and logging configuration.

Grant **Deskflow Fork Test** Accessibility permission on each Mac when requested. Approve Local Network access if prompted. Input Monitoring may also be requested; enable it for the test app. If macOS retains a stale Accessibility entry, remove/re-add the **test app**, leaving the original Deskflow entry available for rollback. The test app uses its own bundle identifier.

If a warning blocks opening this locally built copy, use macOS Privacy & Security → Open Anyway. The start command clears the quarantine attribute only on the copied test app and verifies its signature; it leaves Gatekeeper enabled.

On the **server**, open Configure Server → Advanced and enable:

- **Enable Logi Options+ input compatibility**
- **Forward macOS navigation gestures**

Keep Left / Action 1 and Right / Action 2 as the initial navigation directions. Keep the existing Shift+Tab switch hotkey, lock to computer at startup, Synergy/Barrier selection and Info-level file logging. On the **client**, leave navigation outputs as Back and Forward. Keep the macOS Mission Control middle-button shortcut and Options+ thumb-rest mapping already used by the working setup.

After both sides connect, switch to the client and back once to initialize AWDL focus tracking. The new dropdown controls the already installed worker through the existing private control file. It does not install the newer worker binary from this source tree; a later administrator update can apply the worker's reviewed crash-recovery/focus fixes separately.

## Verify in this order

1. Shift+Tab switches both ways. Edges do not switch computers.
2. After releasing Shift+Tab, vertical and horizontal scrolling both work on the client. Repeat switching several times and test Arc plus another app.
3. Back and Forward follow the physical button assignments on a tab with history. Test the server too.
4. The thumb-rest button opens Mission Control on the active Mac only.
5. Deskflow → Smooth Mode reports **Client active — AWDL suppressed** on both Macs while controlling the client, and **Server active — AirDrop allowed** after returning. Allow several seconds for the log/status update.
6. On **both Macs**, select Allow AirDrop for 10 minutes before using AirDrop during client control. Test a transfer, then Resume automatic mode now on both and switch away/back. Check that cursor movement becomes smooth again.
7. Stop/restart one fork instance, reconnect, and switch away/back. Check input and smoothing again.

Do not log out/reboot during the first temporary test: the previous helper login entries remain installed and would run again at the next login. Once live tests pass, make a separate permanent migration that disables the old agents and selects the fork for login. This package intentionally does not perform that step or overwrite the official app.

## Restore the previous setup

On **each Mac**, in the same package folder:

```sh
/bin/zsh "Restore Previous Setup.command"
```

This stops the fork, saves the post-test settings alongside the backup, restores the original settings/smoothing preference, reloads only the helper agents that were running before the test, and opens `/Applications/Deskflow.app`. It keeps both the private backups and the test app. macOS may request the original app's input permissions again; the script cannot grant them. No root service, network route, VPN setting or system permission is modified by these commands.

The snapshots include TLS material. Keep the backup folder private and do not upload it with diagnostic logs.

## Reproduce the package

Build an arm64 Release tree with `BUILD_OSX_BUNDLE=OFF`, `BUILD_TESTS=OFF`, deployment target 27.0 and the documented Qt/OpenSSL dependencies. Commit source changes first. Then:

```sh
python3 tools/macos-fork-test/bundle.py build/portable dist/fork-test \
  --macdeployqt /opt/homebrew/opt/qtbase/bin/macdeployqt \
  --lrelease /opt/homebrew/opt/qttools/bin/lrelease
```

The script bundles runtime libraries/plugins, records the source revision, rejects remaining absolute dependencies outside macOS system libraries, and ad-hoc signs/verifies the final app. Qt's own optional translation catalogs are not included; unmatched Qt strings fall back to English. Deskflow's existing translation catalogs are included.
