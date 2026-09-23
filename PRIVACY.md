# Privacy Policy for MangaBaka iOS

Last updated: September 23, 2026

This policy explains the behavior of the MangaBaka iOS application in this repository. It is written for the current repository state and may change as the project evolves.

## Scope

This privacy policy applies to **MangaBaka iOS**, the independently maintained client published in this repository.

[MangaBaka](https://mangabaka.org/) is a separate third-party service. Requests sent to MangaBaka are processed under MangaBaka's own policies; this document does not govern MangaBaka's servers, website, accounts, or database.

## MangaBaka account authentication

Sign-in is performed through MangaBaka's OAuth/OpenID authorization experience. MangaBaka iOS must never ask for your MangaBaka password directly. You enter credentials into MangaBaka's authorization experience, not into a custom MangaBaka iOS username/password form.

After authorization, OAuth tokens are used to access the authenticated MangaBaka API. MangaBaka iOS is intended to be a native/public client using Authorization Code with PKCE.

The intended scopes are:

- `openid`: identifies the signed-in session using OpenID Connect.
- `profile`: allows the app to retrieve basic MangaBaka profile information.
- `library.read`: allows the app to read the user's MangaBaka library.
- `library.write`: allows the app to update the user's MangaBaka library.
- `offline_access`: allows a refresh token to keep the session working without requiring sign-in for every use.

Public account integration is still being prepared and must be validated against the final registered MangaBaka client before release. See [docs/OAUTH.md](docs/OAUTH.md).

## Local storage

MangaBaka iOS stores data locally so the application can maintain a session and provide its features:

- OAuth tokens and cached profile data use secure storage. On iOS, `flutter_secure_storage` uses platform secure storage / Keychain.
- MangaBaka library data is cached in the application's local SQLite database.
- Application preferences are stored locally.
- Synchronization metadata is stored locally.
- News, title metadata, and other cache information may be cached locally.
- Sanitized diagnostic logs may be stored locally.

Not all local application data is encrypted. For example, the local SQLite database, ordinary preferences, caches, synchronization metadata, and log files should not be assumed to have application-level encryption.

## Logout

Logout clears MangaBaka iOS's locally stored OAuth credentials and cached profile session, and it clears the locally cached MangaBaka library.

The current implementation does **not** claim to revoke OAuth tokens on MangaBaka's servers or perform a server-side end-session request. Other application preferences, caches, synchronization metadata, or log files may remain until they are cleared through the application or operating system, or until the application and its data are removed.

## Search and API requests

Search and browse requests are sent to MangaBaka APIs. Signed-in library reads and updates are also sent to MangaBaka.

MangaBaka controls server-side processing of requests sent to its service. Review [MangaBaka's privacy policy](https://mangabaka.org/about/privacy) for information about its practices.

## Barcode scanner / camera

Camera permission is requested only when you choose to use the barcode scanner. The camera is used to detect a barcode. MangaBaka iOS does not intentionally upload camera images.

After a barcode is decoded, the resulting ISBN or other identifier is sent to MangaBaka's identifier lookup API so MangaBaka can resolve the relevant book or title.

## Imports

Files that you select for import are processed locally by MangaBaka iOS. Supported parsing includes plain-text, CSV, JSON, XML export, and backup-style formats.

AniList import works differently. When you explicitly request an AniList import, the AniList username you provide is sent to AniList's public GraphQL API to retrieve that public manga list. [AniList](https://anilist.co/) is an independent third-party service with its own policies. MangaBaka iOS does not contact AniList for ordinary local-file imports.

## GitHub

MangaBaka iOS may contact GitHub's API to check this project's releases and updates. GitHub therefore receives normal network metadata associated with that request, such as an IP address and request headers. This project does not control GitHub's privacy practices.

## Diagnostic logs

Diagnostic logs are stored locally. Recent privacy hardening sanitizes or redacts tokens, OAuth values, email addresses, sensitive URL query data, and local user-home paths. Raw stack traces and raw error values are not intentionally persisted into shareable logs.

Logs are not automatically uploaded by MangaBaka iOS. Users can explicitly copy or share diagnostic logs. Sanitization is a risk-reduction measure, not an infallible guarantee, so users should review a log before posting or sharing it publicly.

## Analytics / advertising / crash reporting

The current version of this repository does not include an advertising SDK, behavioral analytics SDK, or third-party crash-reporting SDK in MangaBaka iOS itself. This statement describes this application's current dependencies and does not make claims about MangaBaka or another third-party service.

## Data sale

MangaBaka iOS does not sell personal data.

## Third-party services

Depending on the features you use, MangaBaka iOS may interact with:

- **MangaBaka** for browsing, search, account authorization, profile, library, and identifier lookup requests.
- **GitHub** for project release/update checks and links to project documents.
- **AniList** only when you explicitly use the AniList username importer.
- **External websites** that you choose to open from links in the application.

Each third-party service has its own terms and privacy practices. Opening an external website leaves MangaBaka iOS.

## Deleting local data

Practical options for local data are:

- Use logout to clear the local MangaBaka session/profile credentials and locally cached MangaBaka library.
- Clear diagnostic logs from the Logs screen.
- Remove/uninstall the application and its app data to clear remaining local preferences, databases, caches, synchronization metadata, and logs, subject to operating-system behavior.

MangaBaka iOS does not currently promise server-side MangaBaka account or data deletion. Use MangaBaka's own account controls and policies for data held by MangaBaka.

## Security

Security reporting instructions are in [SECURITY.md](SECURITY.md). Do not publish tokens, credentials, private logs, or sensitive vulnerability details in a public issue.

## Changes

This policy may evolve as the project changes. Git history records revisions to this document, and material application changes should update it.

## Contact

For ordinary, non-sensitive privacy questions, use the repository's [Issues page](https://github.com/Brainer-00/MangaBaka-IOS/issues).

For security-sensitive information, **do not open a public issue**. Use the repository's private vulnerability-reporting process described in [SECURITY.md](SECURITY.md).
