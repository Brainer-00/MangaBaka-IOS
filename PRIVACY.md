# Privacy Policy for MangaBaka iOS

Last updated: September 30, 2026

This policy explains the behavior of the MangaBaka iOS application in this repository.

## Scope

This privacy policy applies to **MangaBaka iOS**, the independently maintained client published in this repository.

[MangaBaka](https://mangabaka.org/) is a separate third-party service. Requests sent to MangaBaka are processed under MangaBaka's own policies; this document does not govern MangaBaka's servers, website, accounts, or database.

## MangaBaka account authentication

Sign-in is performed through MangaBaka's OAuth/OpenID authorization experience in the system browser. MangaBaka iOS does not ask for a MangaBaka password in a custom form.

MangaBaka iOS is a native/public client using Authorization Code with PKCE `S256`. After authorization, OAuth tokens are used to access the authenticated MangaBaka API. The app requests these scopes:

- `openid` to identify the signed-in session through OpenID Connect;
- `profile` to retrieve basic MangaBaka profile information;
- `library.read` to read the user's MangaBaka library;
- `library.write` to update the user's MangaBaka library; and
- `offline_access` to obtain a refresh token so a session can continue without sign-in on every use.

The implementation is described in [docs/OAUTH.md](docs/OAUTH.md).

## Local storage and iOS reinstall behavior

MangaBaka iOS stores data locally so it can maintain a session and provide its features:

- OAuth access, refresh, and ID tokens, token-expiration data, and cached profile state use `flutter_secure_storage`. On iOS, this is Keychain-backed storage.
- MangaBaka library data is cached in the application's local SQLite database.
- Application preferences, synchronization metadata, news, title metadata, and other cache information may be stored locally.
- Sanitized diagnostic logs may be stored locally.

A dedicated installation sentinel is stored in ordinary application preferences outside Keychain. iOS can retain Keychain values after an app is uninstalled while removing ordinary application preferences. When the sentinel is absent and no narrowly validated legacy-install evidence exists, MangaBaka iOS treats the state as a fresh iOS installation, clears retained MangaBaka authentication credentials and cached profile state before allowing session restoration, then writes a sentinel for the current installation. If cleanup or sentinel persistence fails, session restoration is blocked and retried on a later launch.

Normal application updates and relaunches retain the sentinel and preserve the authenticated session. A narrowly validated migration path also preserves sessions for existing installations created before the sentinel was introduced.

Keychain protection does not apply to every local file. The SQLite database, ordinary preferences, caches, synchronization metadata, installation sentinel, and diagnostic log files should not be assumed to have application-level encryption.

## Logout

Explicit logout clears MangaBaka authentication credentials and cached profile state from local secure storage and clears the locally cached MangaBaka library.

Logout does **not** currently claim to revoke OAuth tokens on MangaBaka's servers or perform a guaranteed server-side end-session action. Other application preferences, caches, synchronization metadata, or log files may remain until cleared through the application or operating system, or until the application and its data are removed.

## MangaBaka requests and remote media

Search, browse, profile, library, and identifier-lookup requests are sent to MangaBaka APIs. MangaBaka controls server-side processing of those requests. Review [MangaBaka's privacy policy](https://mangabaka.org/about/privacy) for its practices.

Remote covers, avatars, and similar media may be fetched directly from hosts referenced by MangaBaka data. Those hosts can receive ordinary network metadata such as the device's IP address, request headers, and request timing.

## Website icons from Google

For certain external-link displays, MangaBaka iOS requests website icons from Google's favicon endpoint at `www.google.com/s2/favicons`. When such an icon is loaded, Google receives ordinary network metadata and the requested favicon domain. Google is an independent third party with its own policies.

## Barcode scanner and camera

Camera permission may be explicitly requested during onboarding or when the user chooses barcode scanning. The camera is used to detect a barcode; MangaBaka iOS does not intentionally upload camera images.

After a barcode is decoded, the resulting ISBN or other identifier is sent to MangaBaka's identifier-lookup API so MangaBaka can resolve a book or title.

## Imports

Files selected for import are processed locally by MangaBaka iOS. Supported parsing includes plain-text, CSV, JSON, XML export, and backup-style formats. Imported entries that the user chooses to match or save may cause normal MangaBaka API requests required for those actions.

AniList username import works differently. When the user explicitly requests it, the provided AniList username is sent to AniList's public GraphQL API to retrieve that public manga list. [AniList](https://anilist.co/) is an independent third-party service with its own policies. MangaBaka iOS does not contact AniList for ordinary local-file imports.

## GitHub update checks

MangaBaka iOS may contact GitHub's API to check this project's releases and updates. GitHub receives ordinary network metadata associated with that request, such as an IP address and request headers. This project does not control GitHub's privacy practices.

## Diagnostic logs

Diagnostic logs are stored locally. Logging sanitization redacts or removes tokens, OAuth values, email addresses, sensitive URL query data, local user-home paths, raw stack traces, and raw error values from logs intended to be shareable.

Logs are not automatically uploaded by MangaBaka iOS. Users can explicitly copy or share diagnostic logs. Sanitization reduces risk but is not an infallible guarantee, so users should review a log before posting or sharing it publicly.

## Analytics, advertising, and crash reporting

MangaBaka iOS does not currently bundle an advertising SDK, behavioral analytics SDK, or third-party crash-reporting SDK. This statement describes this application's current dependencies and does not make claims about MangaBaka or another third-party service.

## Data sale

This project does not sell personal data.

## Third-party services

Depending on the features and content used, MangaBaka iOS may interact with:

- **MangaBaka** for browsing, search, authorization, profile, library, and identifier-lookup requests;
- **media hosts referenced by MangaBaka data** for covers, avatars, and similar content;
- **Google** for favicons shown with certain external links;
- **GitHub** for release and update checks and project links;
- **AniList** only when the user explicitly uses the AniList username importer; and
- **external websites** that the user chooses to open from the application.

Each third-party service has its own terms and privacy practices. Opening an external website leaves MangaBaka iOS.

## Deleting local data

Practical options for local data are:

- Use logout to clear local MangaBaka authentication/profile data and the locally cached MangaBaka library.
- Clear diagnostic logs from the Logs screen.
- Remove the application and its app data to clear ordinary local preferences, databases, caches, synchronization metadata, and logs, subject to operating-system behavior. On a later fresh iOS installation, the installation guard clears retained MangaBaka authentication/profile values from Keychain before session restoration.

MangaBaka iOS does not currently promise server-side MangaBaka account or data deletion. Use MangaBaka's own account controls and policies for data held by MangaBaka.

## Security

Security reporting instructions are in [SECURITY.md](SECURITY.md). Do not publish tokens, credentials, private logs, or sensitive vulnerability details in a public issue.

## Changes

This policy may evolve as the project changes. Git history records revisions to this document, and material application changes should update it.

## Contact

For ordinary, non-sensitive privacy questions, use the repository's [Issues page](https://github.com/Brainer-00/MangaBaka-IOS/issues).

For security-sensitive information, **do not open a public issue**. Use the private vulnerability-reporting process described in [SECURITY.md](SECURITY.md).
