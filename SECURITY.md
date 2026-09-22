# Security Policy

## Reporting a security vulnerability

Please do not report security vulnerabilities through public GitHub Issues.

If you discover a security issue affecting MangaBaka iOS, especially one involving authentication, OAuth, access tokens, refresh tokens, deep links, local credential storage, release artifacts, or code signing, please use GitHub's private vulnerability reporting feature.

Open the repository's **Security** tab and select **Report a vulnerability** to submit the report privately.

Maintainer:

[Brainer-00](https://github.com/Brainer-00)

When reporting a vulnerability, include enough information to reproduce and understand the issue, but do not include real credentials, access tokens, refresh tokens, Apple ID credentials, signing certificates, or other sensitive data.

## Scope

Security reports relevant to this repository include issues involving:

- MangaBaka iOS application code
- OAuth and authentication flows
- token or credential storage
- custom URL schemes and deep links
- GitHub Actions workflows
- generated IPA artifacts
- update and release handling
- dependencies used by this project

Issues affecting the upstream MangaBaka service, API, website, or infrastructure should be reported to the appropriate MangaBaka maintainers instead.

## Supported versions

Until the first public MangaBaka iOS release is published, only the latest code on the `main` branch is actively maintained.

After public releases begin, this section will be updated with the supported release versions.

## Disclosure

Please allow reasonable time for a reported vulnerability to be investigated and fixed before publicly disclosing technical details.