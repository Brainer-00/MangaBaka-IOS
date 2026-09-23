# Contributing to MangaBaka iOS

Thanks for your interest in contributing to **MangaBaka iOS**!

MangaBaka iOS is an independently maintained open-source iOS client for the MangaBaka tracking platform. It was developed from the open-source [MangaBaka App](https://github.com/Oazzies/MangaBaka-App) and continues to credit upstream work.

This repository is maintained by [Brainer-00](https://github.com/Brainer-00) and contributors. It focuses on a native-feeling iPhone/iPad experience, iOS compatibility, sideloading, release tooling, privacy-conscious account integration, documentation, and compatibility with upstream where practical.

MangaBaka iOS is not an official MangaBaka release and is not affiliated with or endorsed by MangaBaka or the original maintainers.

## Project documents

Contributors should review the policies relevant to their change:

- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)
- [Attribution & Data Sources](ATTRIBUTION.md)
- [Terms of Use](TERMS.md)

## Issues and feature requests

If you find a bug or have an idea for the iOS project, please open an issue at:

https://github.com/Brainer-00/MangaBaka-IOS/issues

Before opening a new issue, please check whether a similar issue already exists.

When reporting a bug, include as much useful information as possible, such as:

- iOS version
- iPhone/iPad model
- MangaBaka iOS version
- installation method
- steps to reproduce the problem
- screenshots or logs when relevant

## Code contributions

Pull requests are welcome.

If you want to work on an existing issue, leaving a comment first is encouraged so contributors do not accidentally duplicate work.

Please keep pull requests focused on one change or closely related group of changes.

## Project scope

The primary focus of this repository is the independently maintained MangaBaka iOS client.

Useful contributions include:

- iOS-specific bug fixes
- sideloading improvements
- GitHub Actions and IPA build improvements
- AltStore and SideStore support
- authentication and deep-link handling
- iOS UI or platform compatibility fixes
- documentation
- testing
- keeping the project compatible with upstream MangaBaka changes

Changes to shared Flutter code are also welcome when they are required for the iOS application or improve compatibility without unnecessarily diverging from upstream.

## Prerequisites

The project is built with:

- [Flutter](https://flutter.dev/)
- [Dart](https://dart.dev/)

For local iOS builds, macOS with Xcode is required.

You can use any editor that supports Flutter development.

## Local setup

Clone the repository:

```sh
git clone https://github.com/Brainer-00/MangaBaka-IOS.git
cd MangaBaka-IOS
```

Install Flutter dependencies:

```sh
flutter pub get
```

The application expects a `.env` file, but real `.env` files and private variants are intentionally excluded from Git.

Create one from the provided example.

### macOS / Linux

```sh
cp .env.example .env
```

### PowerShell

```powershell
Copy-Item .env.example .env
```

An empty client ID is sufficient for builds that do not require MangaBaka account login.

OAuth login requires a valid MangaBaka OAuth client configuration. MangaBaka iOS uses a native/public OAuth client model, and a client secret must not be embedded in the app, repository, IPA, or environment file. Client IDs are configuration values and are not passwords.

Never commit:

- OAuth access, refresh, or ID tokens
- client secrets
- Apple IDs, passwords, app-specific passwords, or session credentials
- signing keys, private keys, or certificates
- provisioning profiles containing private distribution information
- private `.env` variants

If a secret is committed, treat it as compromised and rotate or revoke it; removing it from the latest file is not sufficient.

## Building for iOS

A normal local Flutter iOS build can be started with:

```sh
flutter build ios --release --no-codesign
```

This repository also contains GitHub Actions automation for generating an unsigned IPA suitable for sideloading.

## Testing

Before submitting a pull request, please test the affected functionality where possible.

For iOS-specific changes, testing on a physical iPhone or iPad is preferred when the feature cannot be fully validated in the simulator.

Also run:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

when your change affects code covered by the Flutter test suite.

## Pull requests

When opening a pull request:

- explain what the change does
- explain why the change is needed
- mention any related issue
- include screenshots for visible UI changes
- mention how you tested the change
- avoid including unrelated formatting or generated-file changes

Pull requests may be adjusted before merging to keep the iOS project maintainable and compatible with upstream MangaBaka development.

## Upstream MangaBaka

This project is based on the original:

[Oazzies/MangaBaka-App](https://github.com/Oazzies/MangaBaka-App)

Where practical, changes from upstream MangaBaka will continue to be incorporated into MangaBaka iOS.

If an issue originates in the original MangaBaka application rather than this iOS distribution, it may be more appropriate to report it upstream.

## Translations

MangaBaka translations are stored in:

```text
assets/lang/languages.json
```

Translation changes should preserve the existing structure and keys.

## License

MangaBaka iOS is distributed under the Apache License 2.0 in accordance with the license of the upstream MangaBaka App.

By contributing code to this repository, you agree that your contribution may be distributed under the repository's license.

## Attribution

MangaBaka iOS is an independently maintained open-source project.

The original MangaBaka application and its upstream source code are maintained by Oazzies and the MangaBaka contributors.

This project is not an official MangaBaka release and is not affiliated with or endorsed by MangaBaka or the original project maintainers.
