# macOS input fixes

## What is integrated

The newer official Deskflow base uses `OSXComputer`. The two navigation commits from Andy D.K Lee's community fork were adapted to those interfaces, the newer settings/reset lifecycle, and the existing versioned keyboard packets. Their original authorship is retained in Git history.

The server recognizes macOS swipe gestures and maps two chosen directions to configurable actions. Navigation forwarding is opt-in and applies while controlling a client. Direction detection and manual mappings are available in Configure Server → Advanced. By default, positive X maps to Left / Action 1 / Back; negative X maps to Right / Action 2 / Forward. This matches the verified MX Master button assignment. The neutral gesture envelope produces no navigation action.

Fork clients receive a protocol-1.9 navigation action. On macOS, the default Back/Forward outputs synthesize Command–[ and Command–] through Deskflow's key-state machinery. On other platforms they synthesize extra mouse buttons. Client settings also support Ignore and custom shortcuts. Recorded Mac shortcuts translate Qt's Command/Control convention into physical Deskflow modifiers and use the normal key-handling path, including secure-attention emulation where supported. Older clients receive the extra-button fallback rather than the new action packet; installing this fork on both Macs is needed for the native Mac shortcut behavior.

## Options+ compatibility

Enable **Configure Server → Advanced → Enable Logi Options+ input compatibility**. It is disabled by default. The preference is `server/macOptionsCompatibilityEnabled`.

The primary computer retains its normal HID capture tap and adds a session-stage tap for other-button down/up events. While the client is active, middle clicks attributed to `logioptionsplus_agent` are copied, tagged and reposted at HID for ordinary Deskflow forwarding. The original is consumed. Tagged replacements cannot relay again. Ordinary HID middle clicks are already consumed before SESSION while remote, and local-server clicks are left unchanged. Source lookup uses the current event PID rather than a fixed Options+ PID.

When the HID callback consumes a physical Shift release while remote, it also copies that release to SESSION so local mouse drivers can clear their modifier state. The primary callback knows it will consume the original, so no separate monitor, timestamp matcher, process watcher or tap-order watchdog is needed. Local-server releases, synthetic releases, tagged copies, Shift presses, and releases with another Shift still held are excluded. The client receives the original modifier event through the normal Deskflow path.

Input configuration is published as a lock-free atomic snapshot so the capture thread cannot race with live settings updates or observe mixed direction mappings. Both taps share Deskflow's event-tap run loop and are removed on disable. A timed-out session tap is re-enabled when Accessibility permission remains available. If that tap cannot be created, Deskflow logs the compatibility limitation.

This compatibility path registers no additional typed-key listener and logs no typed characters. Existing Deskflow input capture remains unchanged apart from the described routing.

## Mouse and switching setup

On the server, keep Options+ thumb-rest set to **Advanced click → Middle click**, including any application-specific profiles. On the Mac client, assign Mission Control to **Middle Mouse Button** in macOS settings. The native fix forwards the click; it does not alter the OS shortcut.

Keep **Shift+Tab → Switch to next computer** as the Deskflow hotkey. Enable **lock to computer at startup** to prevent mouse-edge crossover while retaining hotkey switching. These are existing Deskflow settings, not new defaults imposed by this fork.

Stop the standalone Deskflow MX Relay before testing the native input features; otherwise it can intercept the same Options+ events ahead of the fork. No existing installed app or service is replaced by building this repository.

## Optional AWDL controller

Build with `BUILD_MACOS_SMOOTH_MODE=ON` to produce the optional package under `build/tools/macos-smooth-mode/`. This adds the previously validated AWDL worker, installer and DF menu control as source-controlled build targets. It does not install or start them.

Administrator installation is separate on each Mac. The controller follows ordered Deskflow Info logs, disables `awdl0` while the client is active, suppresses unexpected re-enabling, and releases its suppression on return to the server or loss of known focus. The menu offers automatic mode and a temporary AirDrop override. During a transfer while controlling the client, allow AirDrop on both Macs. Suppression and AirDrop cannot operate simultaneously on the same interface.

The fork now provides these controls in its own macOS menu-bar dropdown under **Smooth Mode**, including controller status and log access. It uses the existing worker/control-file protocol and needs no additional permission for those controls. The separate DF menu app can be unloaded while using the fork; the privileged worker remains installed. A [reversible two-Mac test package](../tools/macos-fork-test/README.md) prepares the fork and temporarily unloads the old menu and input relay without replacing the official app.

The privileged worker can change only `awdl0`. It has no network listener, arbitrary command facility, input capture, setuid bit or sudoers modification. Its installer and removal behavior are described in the [component guide](../tools/macos-smooth-mode/README.md). The existing deployed controller may remain in use; this component retains its service labels and log format.

## Development build on macOS

The local validation used Apple Silicon, macOS 27.0.1, Qt 6.12.0, OpenSSL 3.6.3 and Apple Clang. An Intel build and live two-Mac tests were not performed for this port.

Install the normal upstream build dependencies. With Homebrew's split Qt packages:

```sh
brew install cmake ninja qtbase qttools openssl@3
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_TESTS=ON -DSKIP_BUILD_TESTS=ON \
  -DBUILD_INSTALLER=OFF -DBUILD_OSX_BUNDLE=OFF \
  -DBUILD_MACOS_SMOOTH_MODE=ON \
  -DCMAKE_PREFIX_PATH="$(brew --prefix qtbase);$(brew --prefix qttools)" \
  -DQt6LinguistTools_DIR="$(brew --prefix qttools)/lib/cmake/Qt6LinguistTools" \
  -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)"
cmake --build build --target Deskflow deskflow-core macos-smooth-mode \
  OSXComputerTests OSXInputCompatibilityTests KeySequenceTests SettingsTests \
  KeyStateTests ComputerNavigationTests ClientProxyTests ServerProxyTests ServerConfigDialogTests -j 6
```

This development configuration produces `build/bin/Deskflow` and `build/bin/deskflow-core`, rather than installing or replacing `/Applications/Deskflow.app`. The optional helper package builds beside them. Use the upstream packaging instructions when preparing a distributable app bundle.

## Validation

After the review corrections on 18 October 2026, both Deskflow executables and the optional helper package built successfully. All nine selected native/protocol/settings suites and all three AWDL suites passed. The pinned clang-format 20.1.0 check, REUSE license lint and strict helper-app signature verification passed. The installed Deskflow and helpers were not replaced.

The subsequent integrated Smooth Mode menu adds `MacSmoothModeMenuTests`: controls use the existing worker protocol, stale/missing status disables controls, expired AirDrop overrides are reflected, construction leaves preferences untouched, and an invalid/symlinked control file reports an error without replacing it. The expanded set of ten native/GUI suites plus three simulated helper suites passes. The temporary migration commands are syntax-checked; their actual service stop/start and rollback still require the live two-Mac test.

```sh
ctest --test-dir build/src/unittests \
  -R '^(MacSmoothModeMenuTests|OSXComputerTests|OSXInputCompatibilityTests|KeySequenceTests|SettingsTests|KeyStateTests|ComputerNavigationTests|ClientProxyTests|ServerProxyTests|ServerConfigDialogTests)$' \
  --output-on-failure
ctest --test-dir build/tools/macos-smooth-mode --output-on-failure
```

The regression tests also complete a real in-memory client handshake for 1.6–1.9 and dispatch navigation through the client/computer stack, without opening sockets. Custom shortcut tests verify recorded Mac modifiers and normal secure-attention routing through a recording platform.

The regression tests cover gesture directions and focus/enable gating; source and button filtering; event-copy fidelity and loop prevention; physical Shift-release eligibility; restoration of the Command modifier after a shortcut; current and legacy navigation packets; invalid action slots; frozen keyboard packet formats; shortcut parsing; settings defaults; and offscreen GUI save/reload/reset while retaining existing protocol and cursor-lock settings. The input tests construct or record synthetic events but do not post them to the desktop.

AWDL policy and installer tests are non-installing. The integration tests use fake interface/core files for both roles and cover focus changes, historical log rejection, unexpected re-enabling, AirDrop override/expiry, disable, rotation, core loss/restart, disconnect, symlink rejection, crash recovery with temporary interface errors, unrelated incoming handshake failures and shutdown restoration. They do not change real interfaces.

Unit and simulated tests do not replace live end-to-end validation of the new native capture paths. Before using the new build daily, test switching, both wheels, Back/Forward, Mission Control, host-local behavior, disconnect/reconnect and the AWDL/AirDrop round trip on both physical Macs.

These changes were prepared with OpenAI Codex assistance. Companion behavior was tested by the user on the physical setup; the native fork's build and automated validation are described above. No claim of upstream maintainer review or acceptance is made.

The [review findings and corrections](macos-port-review.md) explain why additional regressions were added after the initial port.
