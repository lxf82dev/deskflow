# Deskflow — macOS input fixes

This personal fork tracks [official Deskflow](https://github.com/deskflow/deskflow) and adds fixes developed for a Mac server and Mac client using a Logitech MX Master 3S with Logi Options+.

- Configurable Back/Forward gesture forwarding, ported from [Andy D.K Lee's community fork](https://github.com/andy5090/deskflow-andy-custom), with original commit authorship retained.
- Native Mac client navigation through Command–[ / Command–].
- An opt-in server compatibility setting for Options+ middle clicks and missing local Shift releases after switching computers.
- An optional administrator-installed AWDL controller that suppresses AWDL while controlling the client and restores it on return to the server, with an AirDrop override.

See [setup, build instructions and validation](docs/macos-input-fixes.md). The AWDL component is documented separately in [tools/macos-smooth-mode](tools/macos-smooth-mode/README.md).

The native changes have been built and tested locally. Testing the modified Deskflow on both physical Macs remains a deployment step. The original standalone helpers were validated on that setup; they should be stopped before testing the corresponding native input features.

For the upstream project's downloads and general documentation, see the [original README](.github/README.md). This fork is independent of Deskflow's maintainers and Logitech.
