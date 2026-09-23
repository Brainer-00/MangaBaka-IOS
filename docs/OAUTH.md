# MangaBaka iOS OAuth Architecture

This document records the intended authentication architecture for MangaBaka iOS. It describes the native/public client model; it does not claim that the final production MangaBaka client registration is complete.

## Native/Public OAuth client and flow

MangaBaka iOS is designed as a **native/public OAuth client** using:

- OAuth 2.0 Authorization Code flow
- PKCE with the `S256` code challenge method
- system/browser authorization instead of collecting a username and password in the app
- redirect URI `io.github.brainer00.mangabaka-ios://oauthredirect`

A client secret must not be embedded in this repository, application bundle, or IPA. A distributed native application cannot keep an embedded secret confidential.

## Intended scopes

The intended MangaBaka scopes are:

- `openid`
- `profile`
- `library.read`
- `library.write`
- `offline_access`

Scope meanings and the application privacy impact are documented in [PRIVACY.md](../PRIVACY.md).

## Token handling

OAuth access, refresh, and ID tokens are stored through `AuthStorage`, which uses secure platform storage through `flutter_secure_storage`. On iOS, this maps to Keychain-backed storage.

Application logging must not expose access tokens, refresh tokens, ID tokens, authorization codes, PKCE values, or OAuth `state` values. Diagnostic logging should preserve only the minimum sanitized context required for troubleshooting.

## Configuration

The production OAuth client ID should be configured externally for the build environment. A client ID identifies the public client and is not treated as a password.

`.env` is a local/build configuration mechanism. It is **not** a secret-storage mechanism for a native client secret, and no client secret should be added to `.env`, source code, CI configuration, or a built IPA.

## Known pre-release authentication work

- MangaBaka OAuth application registration still needs to be finalized as a public/native application.
- Refresh-token revocation and end-session behavior still need validation against the real registered client.
- iOS AppAuth and authorization/cache behavior need a separate security review.
- Physical-device sign-in, token refresh, logout, and reinstall tests are required.

These are release-readiness tasks. They are not implemented or resolved by the documentation and Privacy & Legal UI changes that introduced this document.
