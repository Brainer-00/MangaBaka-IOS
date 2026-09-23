# MangaBaka iOS Release Checklist

This checklist tracks unresolved work required before a public release. An unchecked item is not approved, implemented, or verified merely because it appears here.

## Identity

- [ ] Replace the inherited/upstream app icon with an original MangaBaka iOS icon.
- [ ] Perform a separate internal Dart package rename from `mangabaka_app` if desired or required for derivative identity.
- [ ] Confirm the GitHub repository description and homepage metadata.

## OAuth

- [ ] Register MangaBaka iOS as a MangaBaka Native App.
- [ ] Enable public application / PKCE behavior.
- [ ] Configure the real client ID.
- [ ] Verify the exact redirect URI: `io.github.brainer00.mangabaka-ios://oauthredirect`.
- [ ] Validate the requested scopes.
- [ ] Test login on a real iPhone.
- [ ] Test token refresh.
- [ ] Test an expired token.
- [ ] Test logout.
- [ ] Evaluate server-side token revocation and end-session behavior.
- [ ] Evaluate iOS AppAuth authorization-URL and token-cache mitigation.

## Security

- [ ] Validate external URLs before launching remote URLs.
- [ ] Add shared MangaBaka search/API rate-limit handling.
- [ ] Run a dependency vulnerability audit.
- [ ] Review and test a `flutter_secure_storage` migration/upgrade.
- [ ] Verify that Git history and the current tree contain no secrets.
- [ ] Run final sanitized-log regression tests.

## Release behavior

- [ ] Make the application version a single source of truth.
- [ ] Define prerelease versus stable update behavior.
- [ ] Review inherited Windows executable self-update behavior.
- [ ] Validate the generated IPA artifact.
- [ ] Complete a physical-device smoke test.

## Repository

- [ ] Configure main-branch rules or a ruleset.
- [ ] Require quality CI before merge when appropriate.
- [ ] Optionally require iOS build CI.
- [ ] Review Dependabot output.
- [ ] Create the first proper release notes.
- [ ] Verify `LICENSE`, `ATTRIBUTION.md`, `PRIVACY.md`, and `TERMS.md` links.
