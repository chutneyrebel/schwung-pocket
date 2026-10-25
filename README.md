# Schwung Pocket

**A mobile companion for Ableton Move running Schwung.**

Schwung Pocket is an iPhone companion app designed to make controlling, navigating, and working with Schwung on Ableton Move more convenient. It brings the Move interface and Schwung Manager closer to your fingertips, with dedicated tools for sound design, parameter control, and file access.

The project aims to create a streamlined mobile workflow for music producers who want to spend more time creating and less time navigating menus.

## Features

### Mirror
Access the Ableton Move interface from your iPhone through a mobile-friendly mirror view. The goal is to make the interface easier to navigate, including fullscreen viewing and improved use of the available screen space.

### Schwung Manager
Access the Schwung Manager interface running on your Move, using the device's local network connection.

### SchwungTroller
A dedicated control interface for supported Schwung instrument parameters. The module is designed to present parameters using reusable rotary controls, appropriate selectors, and instrument-specific groupings.

### Sample Lab
A dedicated workspace for sample-related tools and workflows. Available functionality depends on the current implementation.

### Groove Toolkit
A dedicated workspace for groove-related tools and workflows. Available functionality depends on the current implementation.

### Files
Access the file interface provided by Schwung to work with the files available on your Move. Supported operations depend on the capabilities exposed by the device.

### Home and Quick Control
A central place for accessing frequently used app features. The project aims to support configurable shortcuts and quick access to the modules you use most.

## Requirements

- An iPhone running a compatible version of iOS.
- An Ableton Move running Schwung.
- A working local network connection between the iPhone and Ableton Move.
- The Schwung Manager interface accessible from the device.

The default local Manager address used during development is:

`http://move.local:7700`

The remote interface and file interface are available at:

- Mirror interface: `http://move.local:7700/remote-ui`
- Files: `http://move.local:7700/files`

These addresses assume your Move is reachable at `move.local` on your local network. Network configuration may differ.

## Installation and development

Schwung Pocket is an iOS application developed with Swift and SwiftUI.

The project can be built using Xcode on macOS or through a correctly configured GitHub Actions workflow using Apple's iOS SDK.

For cloud builds, use the repository's existing GitHub Actions workflow. Follow the workflow instructions to build the app and retrieve its output artifact.

Installing a build on a physical iPhone may require signing the app with a compatible Apple development certificate or using an appropriate sideloading workflow.

## Project status

Schwung Pocket is an actively developed community project. Features, interface behaviour, and compatibility may change between versions.

Some capabilities depend on the remote-control protocol exposed by Schwung Manager. Instrument parameter types, track-to-slot mapping, Master FX and Tool control, transport control, and certain file operations require verification against a running Ableton Move.

A successful source-code check or cloud build does not by itself confirm that every feature works correctly on the physical device.

## Roadmap

Planned areas of improvement include:

- A more responsive mirror interface with better orientation and fullscreen behaviour.
- Configurable navigation and quick controls.
- Expanded parameter support and instrument-specific organisation.
- Reliable mapping between Schwung tracks and remote-control destinations.
- Investigation of Master FX, Tool, and transport control.
- Better mobile access to the Schwung file interface.
- Improved accessibility, usability, and connection handling.

## Documentation

- [Schwung documentation](https://schwung.dev/manual.html)
- [Schwung Pocket source repository](https://github.com/chutneyrebel/schwung-pocket)

## Disclaimer

Schwung Pocket is an independent community project. It is not affiliated with, endorsed by, or officially supported by Ableton.

Ableton Move and Ableton are trademarks of their respective owners. Schwung is a separate project. Please refer to the relevant projects for their own licensing and usage terms.

## Contributing

Contributions, bug reports, and suggestions are welcome. When reporting an issue, include:

- Your Schwung Pocket version and build number.
- Your iOS version.
- Your Schwung version, where available.
- The steps needed to reproduce the problem.
- Relevant error messages or screenshots, with private information removed.

When proposing changes to remote-control behaviour, include protocol evidence where possible rather than assuming undocumented message formats.
