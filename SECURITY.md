# Security Policy

## Supported versions

Security fixes are provided for the currently maintained v1.0 patch line. Support moves forward with maintained patch releases and is not a promise of indefinite support for every future 1.x version.

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |
| Pre-1.0 builds | No |

## Reporting a security vulnerability

Please do not report security vulnerabilities through public GitHub Issues.

If you discover a security issue affecting MangaBaka iOS, especially one involving authentication, OAuth, access tokens, refresh tokens, deep links, local credential storage, release artifacts, or code signing, use GitHub's Private Vulnerability Reporting feature.

Open the repository's **Security** tab and select **Report a vulnerability** to submit the report privately.

Maintainer: [Brainer-00](https://github.com/Brainer-00)

Include enough information to reproduce and understand the issue, but do not include real credentials, access tokens, refresh tokens, Apple account credentials, signing certificates, private keys, sensitive personal information, or unredacted private logs.

Authentication design and privacy behavior are documented in [docs/OAUTH.md](docs/OAUTH.md) and [PRIVACY.md](PRIVACY.md). These documents may help reporters distinguish an intended boundary from a security defect, but they do not limit valid reports.

## Scope

Security reports relevant to this repository include issues involving:

- MangaBaka iOS application code;
- OAuth and authentication flows;
- token or credential storage;
- custom URL schemes and deep links;
- GitHub Actions workflows;
- generated IPA artifacts;
- update and release handling; and
- dependencies used by this project.

Issues affecting the upstream MangaBaka service, API, website, or infrastructure should be reported to the appropriate MangaBaka maintainers instead.

Ordinary non-sensitive questions about this project's privacy documentation may use repository Issues. Vulnerability details and security-sensitive personal information must remain in GitHub's private vulnerability-reporting channel.

## Disclosure

Please allow reasonable time for a reported vulnerability to be investigated and fixed before publicly disclosing technical details.
