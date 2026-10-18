# Deskflow — macOS input fixes

This personal fork tracks [official Deskflow](https://github.com/deskflow/deskflow) and adds fixes developed for a Mac server and Mac client using a Logitech MX Master 3S with Logi Options+.

- Configurable Back/Forward gesture forwarding, ported from [Andy D.K Lee's community fork](https://github.com/andy5090/deskflow-andy-custom), with original commit authorship retained.
- Native Mac client navigation through Command–[ / Command–].
- An opt-in server compatibility setting for Options+ middle clicks and missing local Shift releases after switching computers.
- An optional administrator-installed AWDL controller that suppresses AWDL while controlling the client and restores it on return to the server, with an AirDrop override.

See [setup, build instructions and validation](docs/macos-input-fixes.md). The AWDL component is documented separately in [tools/macos-smooth-mode](tools/macos-smooth-mode/README.md).

The native changes have been built and tested locally. The owner also reports successful live input and switching tests on the two Apple Silicon Macs with a Keychron keyboard and MX Master 3-family mouse. The old input relay and DF menu were unloaded during the test. See the setup guide for test limits and rollback; logout/reboot validation is a separate step.

For the upstream project's downloads and general documentation, see the [original README](.github/README.md). This fork is independent of Deskflow's maintainers and Logitech.
