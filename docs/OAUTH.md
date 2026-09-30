# MangaBaka iOS OAuth Architecture

This document describes the OAuth architecture implemented by MangaBaka iOS v1.0.0.

## Native/public client

MangaBaka iOS is a native/public OAuth client. A distributed application cannot keep an embedded client secret confidential, so no client secret is included in source code, build configuration, the application bundle, or the IPA.

The client ID identifies the public application. It is configured for the build but is not treated as a password.

## Authorization flow

Authentication uses:

- OAuth 2.0 Authorization Code flow;
- PKCE with the `S256` code-challenge method;
- the system browser/authorization session rather than an in-app username/password form; and
- the exact redirect URI `io.github.brainer00.mangabaka-ios://oauthredirect`.

The custom-scheme redirect is validated before an authorization code is accepted. OAuth state and PKCE verification bind the callback to the authorization request.

## Scopes

The current requested MangaBaka scopes are:

- `openid`
- `profile`
- `library.read`
- `library.write`
- `offline_access`

Their user-facing purposes and privacy implications are described in [PRIVACY.md](../PRIVACY.md).

## Token storage

`AuthStorage` stores access, refresh, and ID tokens, access-token expiration data, and cached MangaBaka profile state through `flutter_secure_storage`. On iOS, this is backed by Keychain.

Production authentication storage does not fall back to ordinary preferences. Storage failures are surfaced and fail closed where session or token restoration depends on them. An insecure preference fallback exists only behind an explicit testing option and is not enabled for normal application use.

## Installation-session guard

iOS may retain Keychain entries when an app is uninstalled while removing ordinary application preferences. MangaBaka iOS therefore stores a dedicated installation sentinel outside Keychain.

At startup:

1. If the sentinel exists, normal session restoration proceeds.
2. If the sentinel is absent and narrowly validated legacy-install evidence exists, the app records the sentinel and preserves the existing session during migration.
3. If neither exists, the app treats the launch as a fresh iOS installation, clears retained MangaBaka authentication credentials and cached profile state, then records the new sentinel before session restoration can proceed.
4. If cleanup or sentinel persistence fails, session restoration is blocked and the guard retries on a later launch.

Normal relaunches and application updates preserve the sentinel and authenticated session.

## Expiration and refresh

The application stores access-token expiration information and refreshes access tokens when they are near expiry or expired and a refresh token is available. A successful refresh updates rotated tokens, preserves optional tokens that the provider does not replace, and updates or removes stored expiration data to match the response.

Concurrent callers share one in-flight refresh operation. This single-flight protection avoids duplicate refresh requests and races when a provider rotates refresh tokens.

Authenticated GET requests use controlled unauthorized recovery. After an HTTP 401, the client can force one shared refresh and retry the request once with the replacement access token. A second 401 is not replayed indefinitely, and mutation requests are not automatically replayed by this recovery path.

Explicit structured OAuth errors `invalid_grant` and `invalid_token`, or a missing required refresh token, expire the local session. Generic or transient refresh failures do not use error-message substring matching and do not automatically destroy an otherwise recoverable session.

## Logging boundaries

Application logs must not persist access tokens, refresh tokens, ID tokens, authorization codes, client secrets, PKCE verifier/challenge values, OAuth state, sensitive URL query values, email addresses, local user-home paths, raw exceptions, or raw stack traces.

Diagnostics retain only sanitized operational context such as the operation, HTTP status, page/count, or runtime error type where useful.

## Logout

Local logout clears MangaBaka authentication credentials and cached profile state from secure storage and clears the locally cached MangaBaka library.

Current limitation: logout does **not** claim to revoke MangaBaka server-side OAuth tokens or perform a guaranteed server-side end-session action. Server-side revocation/end-session support may be evaluated separately after v1 without changing the local logout guarantee documented here.

## Verification status

The implemented flow has automated coverage for local logout and authentication-storage behavior, exact OAuth error classification, expiration and refresh behavior, single-flight concurrency, controlled 401 recovery, and the reinstall guard. Physical-device QA covered sign-in, relaunch session preservation, and a true uninstall/reinstall starting logged out.
