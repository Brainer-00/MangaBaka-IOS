# MangaBaka Stack API contract

Stage 4E uses the public [MangaBaka OpenAPI specification](https://mangabaka.org/api.json). All Stack paths below are relative to `https://api.mangabaka.org`.

| Operation | Request | Success data |
| --- | --- | --- |
| List Created, Saved, Following | GET `/v2/my/stacks`, `/v2/my/stacks/saved`, `/v2/my/stacks/followed` | Array of `MyStackV2ListItem` for Created and `StackV2ListItem` for Saved and Following, plus pagination |
| Read detail | GET `/v2/my/stacks/{id}` for editing or `/v2/stacks/{id}` for public and unlisted access | `MyStackV2` or `StackV2` |
| Create | POST `/v2/my/stacks` with a 1–200 character title | `MyStackV2` in draft visibility |
| Edit | PUT `/v2/my/stacks/{id}` with current token, title, description, rating, spoiler, comments, visibility and ordered entries | `MyStackV2` with replacement token |
| Visibility only | PUT `/v2/my/stacks/{id}/visibility` with visibility | ID and visibility. The endpoint has no revision token. |
| Append or insert | POST `/v2/my/stacks/{id}/entries` with series ID and optional note, rank and higher content rating | Rank and new token |
| Series membership | GET `/v2/my/series/{id}/stacks` | Owned stacks with rank if present and `can_add` |
| Delete | DELETE `/v2/my/stacks/{id}` | Envelope with status only. The endpoint has no revision token. |
| Viewer status | GET `/v2/my/stacks/status` with one to 50 repeated `id` parameters | `StackStatusV2` for each requested ID |
| Set or clear viewer state | PUT or DELETE `/v2/my/stacks/{saved,followed,votes}/{id}` without a body | `StackStatusV2` |

The owner list includes drafts and hidden stacks. Public detail returns 404 for drafts, hidden or deleted stacks. Public discovery uses GET `/v2/stacks` or `/v2/stacks/search` and includes public discoverable stacks. Unlisted stacks can be opened by link and appear on the owner's profile. Drafts are owner-only.

The three account lists use `page` (one-based), `limit` (maximum 50), repeated `content_rating` for preview covers and a `pagination.next` URL. The result window is 12,000 rows. Covers contain series IDs and URLs, with up to four slots. Entries are ranked and can have nullable notes, a missing-series issue, and nullable catalogue metadata. Descriptions and notes are Markdown without images. Status returns all three viewer flags, vote/save/follow counts and a Library count that may be null.

## Save and follow

| Action | Saved afterward | Following afterward |
| --- | --- | --- |
| Save | Yes | Existing value |
| Follow | Yes | Yes |
| Unfollow | Yes if already saved | No |
| Unsave | No | No |

Following always implies Saved. Both collection sections use the two flags returned by the server. Before Unsave, the app reads and reconciles both flags while holding the Stack's mutation reservation. A changed relationship stops that attempt. For a followed stack, the app obtains explicit confirmation and reads the relationship again before sending the deletion. An uncertain write triggers status readback only.

The documented relationship DELETE takes the Stack ID and authentication. It has no revision, conditional header or expected-relationship parameter. A write from another MangaBaka client can still arrive between the final status read and the DELETE. The app's reservation controls EirenYu operations for that Stack.

## Editing and failures

The maximum is 100 entries. Public and unlisted stacks require five series that still exist on MangaBaka. A merged or deleted slot stays in rank order until edited and does not count toward five. At most 10% of entries may exceed the stack's content rating. Allowed ratings are safe, suggestive, erotica and pornographic. Description and entry-note limits are 10,000 and 5,000 characters respectively.

The full PUT is the revision-protected way to submit metadata, entry changes and visibility atomically. A stale token returns 409 with `stale_token`. The append endpoint may return 409 with `duplicate_entry`. Read and write failures include 400 validation, 401 authentication, 403 scope or policy errors, 404 unavailable resource, 429 rate limiting and server errors. Timeout, malformed success or a server error can leave the outcome uncertain. The app reads before permitting further writes after such a failure.

The detail response distinguishes a verified MangaBaka 403 or 404 from a network or malformed response. A verified denial invalidates the loaded description, entries and notes for that route. An inaccessible detail can recover through a later successful read. After an uncertain DELETE, an inaccessible detail alone cannot prove that deletion succeeded.

Account reads require `stack.read` and writes require `stack.write`. Permission upgrades request the original Library scopes, offline access and the session's previously verified scopes alongside Stack access. [OAuth scope reference](https://mangabaka.org/developers/concepts/oauth-scopes)
