# MangaBaka iOS v1.0.0 Release Checklist

This checklist records the verified release-candidate state and the small remaining publication boundary for MangaBaka iOS v1.0.0. A checked item is supported by the repository, automated checks, GitHub configuration/audits, or recorded physical-device QA.

## Verified for v1.0.0

### Identity and application behavior

- [x] Product and repository identity use **MangaBaka iOS** with permanent upstream attribution and a clear independent/unofficial disclaimer.
- [x] Version `1.0.0+15` is sourced from `pubspec.yaml` and generated into application version constants.
- [x] The existing MangaBaka iOS logo/icon and sample title/cover fixture are intentionally retained.
- [x] The supported and distributed focus is iPhone/iPad through unsigned IPA sideloading.

### OAuth, storage, and device QA

- [x] Native/public OAuth Authorization Code with PKCE `S256` is implemented without an embedded client secret.
- [x] The exact redirect URI is `io.github.brainer00.mangabaka-ios://oauthredirect`.
- [x] Intended scopes are `openid`, `profile`, `library.read`, `library.write`, and `offline_access`.
- [x] OAuth tokens and cached profile state use Keychain-backed secure storage on iOS.
- [x] The installation sentinel/fresh-install guard clears retained MangaBaka credentials and cached profile state before restoring a session on a detected fresh iOS install.
- [x] Normal updates and relaunches preserve authenticated sessions.
- [x] Refresh-token concurrency is single-flight, and controlled authenticated-GET recovery refreshes and retries once after a 401.
- [x] Structured `invalid_grant` / `invalid_token` failures expire the local session without broad message matching.
- [x] Physical-device QA covered sign-in, relaunch session persistence, a true uninstall/reinstall starting logged out, account/library behavior, and profile refresh restarting consistently from page 1.
- [x] Automated coverage and implementation review verify explicit local logout behavior.

### Security and networking

- [x] Browser/application external URLs are validated as HTTPS before launch.
- [x] Shared MangaBaka API rate-limit coordination handles supported `Retry-After` behavior without automatically replaying mutations.
- [x] Sanitized-logging regression tests cover OAuth/query/email/path redaction and the no-raw-stack/no-raw-error persistence boundary.
- [x] The final authenticated GitHub audit reported zero open Dependabot alerts.
- [x] The final authenticated GitHub audit reported zero open secret-scanning alerts.
- [x] The final authenticated GitHub audit reported zero open code-scanning alerts. CodeQL default setup is intentionally Actions-only; this is not a claim of comprehensive Dart or iOS code analysis.

### Release and repository controls

- [x] Stable and prerelease updater selection accounts for both GitHub metadata and parsed prerelease tags.
- [x] iOS automation builds an unsigned IPA, validates its structure/identity, and generates and verifies a SHA-256 checksum.
- [x] The `main` branch ruleset, required quality status, and `v*` release-tag protection are configured.
- [x] Quality CI covers focused formatting, static analysis, and tests without publishing a release.
- [x] Tag-driven release automation separates publication from manual non-publishing workflow dispatch.

## Final release-freeze items

- [x] Align README, privacy, OAuth, terms, security, attribution, changelog, contribution, and checklist documentation with actual v1 behavior.
- [x] Point the README at the canonical logo asset and remove only its byte-for-byte duplicate README copy.
- [x] Remove the unused direct `meta` dependency through the Flutter resolver without unrelated dependency upgrades.
- [ ] Review and merge the release-freeze pull request.
- [ ] Create the exact version tag and allow the tag-driven workflow to publish the first GitHub release.
- [ ] Verify the published release contains exactly the expected unsigned IPA, checksum, and release notes.

The unchecked items are publication steps and do not indicate missing application functionality in the validated release candidate.

## Accepted/non-blocking limitations

- The internal Dart package identifier remains `mangabaka_app`; it is not a user-facing product name.
- Some non-English translations lag English. Missing keys intentionally fall back to English.
- Local logout clears local credentials/profile state and the cached MangaBaka library but does not promise server-side token revocation or a guaranteed server-side end-session action.
- Shared inherited cross-platform and desktop/Windows-oriented Dart code remains in the repository.
- iOS is the supported/distributed focus of this repository; retained cross-platform code does not imply equivalent release support.
- The application is distributed as an unsigned IPA. Signing, provisioning, installation, and refresh behavior depend on Apple and the user's selected sideloading tool.

## Post-v1 considerations

- Evaluate server-supported OAuth revocation or end-session behavior if MangaBaka exposes an appropriate native-client mechanism.
- Expand translations incrementally while preserving English fallback behavior.
- Reassess optional sideload catalog/integration work only if it can be maintained without weakening release validation.
- Continue routine dependency, GitHub security-alert, physical-device, and upstream-compatibility reviews for future patch releases.
