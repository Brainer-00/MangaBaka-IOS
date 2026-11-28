# Stack boundaries and data ownership

The Stack service validates the API envelope and maps it to Stack models. Every Stack operation captures the verified Library account lease and the current Stack authorization generation. A change in the verified Stack scopes or a same-account grant replacement advances the generation. Library ownership and tracking keep their existing identity and cache.

One account-scoped controller owns the three catalogue sections, detail snapshots and per-stack viewer state. An authorization change clears these snapshots and resets operation reservations. Completion handlers from an earlier generation cannot publish results or release a current reservation. Editors bind to the grant and detail access that opened them. The series-detail picker clears its choices and reloads them after a verified grant change. A verified detail denial clears loaded detail and closes access to its notes, while a transient failure retains the previous detail with a stale label.

The Unsave flow holds the Stack reservation across the authoritative read, any coupled-removal confirmation, the recheck after that confirmation, and the mutation. The same controller reconciles both Saved and Following from verified responses.

Every full edit sends ordered entries, notes and the original revision. The app uses independent readback after ambiguous writes because a retry could replace changes from another device. Delete has no revision precondition on the server, so the app rereads the editable revision immediately before sending it.
