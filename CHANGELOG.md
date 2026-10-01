# Changelog

All notable changes to MangaBaka iOS are documented in this file.

## Unreleased

No changes currently recorded.

## [1.0.0]

Initial MangaBaka iOS release.

### Added

- Independent MangaBaka iOS identity, documentation, and permanent attribution to the upstream MangaBaka App project.
- iPhone/iPad-focused unsigned IPA build and tag-driven release automation for sideload distribution.
- IPA structure and identity validation plus SHA-256 checksum generation and verification.
- Native/public MangaBaka OAuth Authorization Code flow with PKCE `S256` and system-browser authorization.
- Keychain-backed secure storage for OAuth credentials and cached profile state.
- An iOS installation sentinel that clears retained MangaBaka authentication/profile state after a detected fresh install while preserving normal update and relaunch sessions.
- Shared MangaBaka API rate-limit coordination with `Retry-After` handling.
- Central HTTPS validation for browser/application external-link launches.
- Privacy & Legal screens and release documentation for privacy, terms, attribution, OAuth, security reporting, and release readiness.
- Repository governance and security configuration, including quality checks, protected release tags, dependency monitoring, private vulnerability reporting, and main-branch rules.

### Changed

- Made `pubspec.yaml` version `1.0.0+15` the source of truth for generated application version metadata and release artifact naming.
- Hardened diagnostic logging to retain useful operational context while sanitizing OAuth values, URL queries, email addresses, local paths, raw errors, and stack traces.
- Separated stable and prerelease update selection, including fallback classification from parsed version tags when GitHub metadata is inconsistent.
- Polished the native launch experience and removed the duplicate Flutter-rendered splash overlay so the first real Flutter frame follows the native splash.
- Defaulted new installations to the Home experience while preserving an explicit saved start-page preference.
- Updated release-facing documentation for the implemented account, storage, privacy, sideloading, and support boundaries.
- Improved Home startup and refresh behavior with concurrent discovery requests, a stable first-load structure, progressive per-rail population, stale-generation protection, and retryable public-only fallback behavior.
- Reduced hot-path work across library persistence, filtering and autocomplete, browse pagination, metadata refresh, cover-image decoding, HTTP connection reuse, and shared rate-limit recovery.

### Fixed

- Automatically move Plan to Read entries to Reading when chapter or volume progress begins, without rewriting other library states.
- Make optimistic progress updates race-safe, restore progress and state together on failure, and keep progress dialogs open until an awaited update succeeds.
- Improve the mobile Import List layout at phone widths, align multiline title entry to the top-left, and keep the tall editor on normal card-radius geometry instead of the global pill shape.
- Reject declared import files larger than 16 MiB before reading them into memory while retaining internal source and decompression limits.
- Added single-flight refresh protection so concurrent authenticated requests do not race rotating refresh tokens.
- Added controlled one-time 401 recovery for authenticated GET requests without automatically replaying mutation requests.
- Preserved recoverable sessions during transient refresh failures while expiring sessions for exact structured `invalid_grant` and `invalid_token` responses.
- Ensured a fresh iOS reinstall cannot silently restore retained MangaBaka credentials from Keychain.
- Corrected profile refresh so an initial refresh restarts from page 1, replaces stale entries consistently, and resists stale pagination results.
- Corrected update selection so stable users do not receive prereleases and prerelease users can receive eligible prerelease builds.

### Security

- Enforced the exact OAuth redirect URI `io.github.brainer00.mangabaka-ios://oauthredirect` and removed any need for an embedded client secret.
- Validated raw OAuth and external-action endpoints before use and applied exact structured OAuth error classification instead of message substring matching.
- Added secure-storage compatibility and fail-closed session restoration behavior for iOS installation detection failures.
- Added bounded import/decompression handling and input validation for untrusted files and remote URL candidates.
- Added regression coverage for sanitized logs, token refresh, 401 recovery, reinstall behavior, external URLs, update channels, and rate limiting.
