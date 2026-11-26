# Share API

This document is the contract between the Vertep app and a sharing service. With it, a
client can publish a folder as a public link, update it, read its counters, unpublish it,
read a folder that another person published, and confirm that it added titles from that
folder. A service that follows it works with the app, so a fork can run its own service.

**Scope.** This document describes only what a client sends and what it receives. It does
not describe how a service stores links, how it counts views and adds, which titles or slugs
it refuses, or how a website shows a published folder. A service can do those things in any
way that gives the answers below.

Sharing needs an account and no subscription. A person who is not signed in can read a
published folder and add its titles, but cannot publish one.

## Conventions

The conventions of `docs/search-api.md` apply here too:

- Every request goes over HTTPS.
- Request and response bodies are JSON, encoded as UTF-8. A request with a body sends
  `Content-Type: application/json`. Every response body, including an error, is JSON.
- Every path starts with the version prefix `/v1`.
- A client ignores a response field that this document does not name. A service ignores a
  request field that this document does not name.
- "Empty" means the JSON value `null`. A field that can be empty is always present.
- A time is a string in RFC 3339 format, in UTC.
- A character is an extended grapheme cluster, as Swift's `String.count` counts it.

## Base URL, the attested session and the account

A client sends the sharing requests to the same base URL as the requests of
`docs/search-api.md`. With the base URL `https://api.example.com`, the publish request goes
to `https://api.example.com/v1/account/shares`.

Every sharing request needs an attested session: the session token that
`docs/search-api.md` describes in "Attestation and sessions". A client that cannot open an
attested session, for example on the Simulator, cannot send sharing requests.

A sharing request carries one or two headers:

| Header | Value | Sent with |
|---|---|---|
| `Authorization` | `Bearer <session token>` — the attested session token. | Every sharing request. |
| `Account-Token` | `<access token>` — the access token of the signed-in account. | Every request that this document marks "Signed in". |

`docs/account-api.md` describes how a client signs in, gets the access token and renews it.
A client sends each "Signed in" request of this document with the client sequence for a
"Signed in" request in that document.

## Links

A published folder has one link. The link has a link id and one or two addresses:

| Address | Exists |
|---|---|
| `/f/<link id>` | Always. |
| `/u/<username>/<slug>` | Only while the account has a username. |

A website that shows published folders also has the address `/u/<username>`, which lists the
published folders of that account.

A link id has 22 characters of `A-Z`, `a-z` and `0-9`. It does not reveal the folder or the
account. One folder has at most one live link. When a person unpublishes a folder and
publishes it again, the new link has a new link id. The old link id never works again.

The service returns the full addresses of a link in `url` and `namedUrl`. For the Vertep
service, the addresses are on `https://vertep.app`. A client shows and shares the addresses
that the service returns, and does not build them itself.

## The snapshot

A published folder is a snapshot of the folder. The service keeps only these fields of it:

| Field | Type | Meaning |
|---|---|---|
| `title` | string | The title of the published folder. 1 to 100 characters, with no whitespace at the start or the end. |
| `slug` | string | The slug of the `/u/<username>/<slug>` address. 1 to 60 characters of `a-z`, `0-9` and `-`. It starts and ends with `a-z` or `0-9`. |
| `mode` | string | `folder` when the link follows the whole folder, `titles` when it shows titles that the person chose. |
| `titleIds` | list of strings | The titles of the published folder, in the order the link shows them. |
| `version` | integer | The version of the snapshot, from 1 to 9007199254740991. |

Each title id is `tmdb:movie:<id>` for a movie or `tmdb:tv:<id>` for a series, where `<id>`
is the TMDB id: a positive decimal integer of 1 to 10 digits, with no leading zero.
`titleIds` has at most 5000 ids and no id twice. In `titles` mode it has at least one id. In
`folder` mode it can be an empty list.

A snapshot never holds the watched state of a title, or any other field of the folder.

The form of the title and the slug is the form in the table above. The username format in
`docs/account-api.md` does not apply to them. The service also checks them against the names
that it does not allow, as it does for a username, and refuses a title with
`title_not_allowed` or a slug with `slug_not_allowed`. A slug is unique among the live links
of one account. Two accounts can use the same slug.

The service replaces a snapshot only with a snapshot of a higher version. The client sets the
version, and each update of a link has a higher version than every earlier snapshot of that
link.

### The share object

The publish, update and read requests answer with this object:

```json
{
  "share": {
    "linkId": "Ab3dE5fG7hJ9kLmN0pQrSt",
    "url": "https://vertep.app/f/Ab3dE5fG7hJ9kLmN0pQrSt",
    "namedUrl": "https://vertep.app/u/kino/films-to-watch",
    "folderId": "6F1B3C2A-9D4E-4B8F-A1C7-2E5D8F0B4A93",
    "title": "Films to watch",
    "slug": "films-to-watch",
    "mode": "folder",
    "titleIds": ["tmdb:movie:348", "tmdb:tv:1396"],
    "version": 7,
    "publishedAt": "2026-11-25T10:00:00Z",
    "updatedAt": "2026-11-25T10:05:00Z",
    "counters": {
      "views": 12,
      "uniqueViews": null,
      "adds": 1
    }
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `linkId` | string | The link id. |
| `url` | string | The `/f/<link id>` address. |
| `namedUrl` | string or empty | The `/u/<username>/<slug>` address. Empty while the account has no username. |
| `folderId` | string | The folder id, as the client sent it in the publish request. |
| `title` | string | The title of the snapshot. |
| `slug` | string | The slug of the snapshot. |
| `mode` | string | The mode of the snapshot. |
| `titleIds` | list of strings | The title ids of the snapshot, in order. |
| `version` | integer | The version of the snapshot. |
| `publishedAt` | string | The time of the publish request that made this link. |
| `updatedAt` | string | The time the service accepted the snapshot that it keeps now. |
| `counters` | object | The counters of the link. See "Counters" below. |

### Counters

| Field | Type | Meaning |
|---|---|---|
| `counters.views` | integer | The number of views of the link. |
| `counters.uniqueViews` | integer or empty | The number of different visitors of each UTC day, added up over the days. Empty when this number is less than 5. |
| `counters.adds` | integer | The number of installations of the app that confirmed an add from this link. |

When `uniqueViews` is empty, the client shows "fewer than 5". The counters can lag behind
the latest views and adds. An unpublish deletes the counters with the link.

## Publish, update and unpublish

### Publish a folder

Signed in.

```
POST /v1/account/shares
Authorization: Bearer <session token>
Account-Token: <access token>
Content-Type: application/json
```

```json
{
  "folderId": "6F1B3C2A-9D4E-4B8F-A1C7-2E5D8F0B4A93",
  "title": "Films to watch",
  "slug": "films-to-watch",
  "mode": "folder",
  "titleIds": ["tmdb:movie:348", "tmdb:tv:1396"],
  "version": 1
}
```

| Field | Type | Meaning |
|---|---|---|
| `folderId` | string | The id of the folder on the device: a UUID in its standard text form. |
| `title` | string | As in "The snapshot". |
| `slug` | string | As in "The snapshot". |
| `mode` | string | As in "The snapshot". |
| `titleIds` | list of strings | As in "The snapshot". |
| `version` | integer | As in "The snapshot". |

The service makes a new link with a new link id, and answers `200 OK` with the share object.

If the folder already has a live link, the service first unpublishes that link, as
"Unpublish a folder" describes, and then makes the new link. Thus a client that sent a
publish request and got no answer can send it again: the folder still has one live link.

Errors: `invalid_request`, `invalid_title`, `invalid_slug`, `invalid_title_ids`,
`title_not_allowed`, `slug_not_allowed`, `slug_taken`, `access_token_expired`,
`session_expired`, `too_many_requests`, `unavailable`.

### Update a published folder

Signed in.

```
PUT /v1/account/shares/<link id>
Authorization: Bearer <session token>
Account-Token: <access token>
Content-Type: application/json
```

```json
{
  "title": "Films to watch",
  "slug": "films-to-watch",
  "mode": "folder",
  "titleIds": ["tmdb:movie:348", "tmdb:tv:1396", "tmdb:movie:603"],
  "version": 8
}
```

| Field | Type | Meaning |
|---|---|---|
| `title` | string | As in "The snapshot". |
| `slug` | string | As in "The snapshot". |
| `mode` | string | As in "The snapshot". |
| `titleIds` | list of strings | As in "The snapshot". |
| `version` | integer | As in "The snapshot". It is higher than the version of every earlier snapshot of this link. |

The request sends the whole snapshot, and the service replaces every field of the snapshot.
The link id and `url` do not change. A new slug changes `namedUrl`, and the client shows the
`namedUrl` of the latest response.

The service answers `200 OK` with the share object. If the version is not higher than the
version of the snapshot that the service keeps, the service changes nothing and answers
`stale_version`.

Errors: `invalid_request`, `invalid_title`, `invalid_slug`, `invalid_title_ids`,
`title_not_allowed`, `slug_not_allowed`, `slug_taken`, `stale_version`, `link_not_found`,
`access_token_expired`, `session_expired`, `too_many_requests`, `unavailable`.

### Read the link and its counters

Signed in.

```
GET /v1/account/shares/<link id>
Authorization: Bearer <session token>
Account-Token: <access token>
```

The service answers `200 OK` with the share object.

Errors: `invalid_request`, `link_not_found`, `access_token_expired`, `session_expired`,
`too_many_requests`, `unavailable`.

### Unpublish a folder

Signed in.

```
DELETE /v1/account/shares/<link id>
Authorization: Bearer <session token>
Account-Token: <access token>
```

The service deletes the snapshot and the counters of the link. After that, every address of
the link answers `folder_unavailable`, and the link id never works again. The service
answers `204 No Content`, with no body. It also answers `204 No Content` when this account
has no live link with this link id.

Errors: `invalid_request`, `access_token_expired`, `session_expired`, `too_many_requests`,
`unavailable`.

When an account is deleted, the service deletes its links too.

## Read a published folder

These requests read a folder that any account published. They are not "Signed in": a client
sends only the attested session token.

A link that never existed, that was unpublished, or that belongs to a blocked or a deleted
account gets one answer: `folder_unavailable`. A link id, a username or a slug in the path
that does not have its form, for example a link that a messenger cut short, gets the same
answer. A client cannot tell these cases apart.

### Read a folder by its link id

For the address `/f/<link id>`:

```
GET /v1/shares/<link id>
Authorization: Bearer <session token>
```

Response `200 OK`:

```json
{
  "folder": {
    "linkId": "Ab3dE5fG7hJ9kLmN0pQrSt",
    "title": "Films to watch",
    "titleIds": ["tmdb:movie:348", "tmdb:tv:1396"]
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `folder.linkId` | string | The link id. The client sends it to confirm an add. |
| `folder.title` | string | The title of the published folder. |
| `folder.titleIds` | list of strings | The title ids of the published folder, in order. The list can be empty. |

The client gets the titles, the posters and the other details of each title with the title
details request of `docs/search-api.md`, at most 20 ids in one request.

Errors: `invalid_request`, `folder_unavailable`, `session_expired`, `too_many_requests`,
`unavailable`.

### Read a folder by its username and slug

For the address `/u/<username>/<slug>`:

```
GET /v1/users/<username>/shares/<slug>
Authorization: Bearer <session token>
```

The service changes uppercase letters `A-Z` in the username to lowercase, as
`docs/account-api.md` describes. For a name that an account had before a change, and that
still points to the new name, the service answers as for the new name.

The response `200 OK` has the same body as "Read a folder by its link id". An account with
no username has no folder at this address.

Errors: `invalid_request`, `folder_unavailable`, `session_expired`, `too_many_requests`,
`unavailable`.

### Read the published folders of a username

For the address `/u/<username>`:

```
GET /v1/users/<username>/shares
Authorization: Bearer <session token>
```

The service reads the username as for "Read a folder by its username and slug".

Response `200 OK`:

```json
{
  "username": "kino",
  "folders": [
    {
      "linkId": "Ab3dE5fG7hJ9kLmN0pQrSt",
      "slug": "films-to-watch",
      "title": "Films to watch",
      "titleCount": 2
    }
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `username` | string | The current username of the account. |
| `folders` | list | The live links of the account. It has at least one link. |
| `folders[].linkId` | string | The link id. The client reads the folder with "Read a folder by its link id". |
| `folders[].slug` | string | The slug of the link. |
| `folders[].title` | string | The title of the published folder. |
| `folders[].titleCount` | integer | The number of title ids of the published folder. |

When `folders` has one link, the client opens that folder directly. The service answers
`folder_unavailable` for a username that no account has, and for an account that has no live
link.

Errors: `invalid_request`, `folder_unavailable`, `session_expired`, `too_many_requests`,
`unavailable`.

## Confirm an add

The client confirms an add after the person added titles from a published folder to their
own folder. It sends the confirmation only when it added at least one title. It does not
send one when every title of the published folder was already in the folder.

```
POST /v1/shares/<link id>/adds
Authorization: Bearer <session token>
```

The request has no body. It is not "Signed in".

The service counts one add per installation of the app and link. A second confirmation from
the same installation for the same link changes nothing. The service answers
`204 No Content`, with no body, to the first confirmation and to every later one.

Errors: `invalid_request`, `folder_unavailable`, `session_expired`, `too_many_requests`,
`unavailable`.

## Errors

An error response has the body that `docs/search-api.md` describes in "Errors":

```json
{
  "error": {
    "code": "slug_taken",
    "message": "Another live link of this account has this slug."
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `error.code` | string | One of the codes below. The client acts on this field. |
| `error.message` | string | A description for a developer. The client does not show it to a user. |

| Status | Code | Meaning | Returned by | What the client does |
|---|---|---|---|---|
| 400 | `invalid_request` | The request is malformed, a field is missing, or a field has the wrong type. A `folderId` that is not a UUID, a `mode` that is not `folder` or `titles`, a `version` outside its range, or a link id in the path of an owner request that does not have its form. | Every request. | Reports that the operation failed. No retry. |
| 400 | `invalid_title` | The title is empty, has more than 100 characters, or has whitespace at the start or the end. | Publish, update. | Asks the person for another title. |
| 400 | `invalid_slug` | The slug does not have 1 to 60 characters of `a-z`, `0-9` and `-`, or starts or ends with `-`. | Publish, update. | Asks the person for another slug. |
| 400 | `invalid_title_ids` | `titleIds` has more than 5000 ids, has an id twice, has an id that is not `tmdb:movie:<id>` or `tmdb:tv:<id>`, or is empty in `titles` mode. | Publish, update. | Reports that the operation failed. No retry. |
| 401 | `session_expired` | The attested session token is missing, has expired, or the service does not know it. | Every request. | Opens a new attested session as `docs/search-api.md` describes, and sends the request again, once. |
| 401 | `access_token_expired` | The access token is missing, has expired, or the service does not know it. | Every "Signed in" request. | Refreshes the session as `docs/account-api.md` describes, and sends the request again, once. |
| 404 | `link_not_found` | This account has no live link with this link id. | Update, read the link. | Marks the folder as not published. No retry. |
| 404 | `folder_unavailable` | The link never existed, was unpublished, or belongs to a blocked or a deleted account. For a username: no account has it, or the account has no live link. A link id, a username or a slug in the path that does not have its form gets this answer too. | Read a folder, read the folders of a username, confirm an add. | Tells the person that the folder is unavailable. No retry. |
| 409 | `title_not_allowed` | The service does not allow this title. | Publish, update. | Asks the person for another title. |
| 409 | `slug_not_allowed` | The service does not allow this slug. | Publish, update. | Asks the person for another slug. |
| 409 | `slug_taken` | Another live link of this account has this slug. | Publish, update. | Asks the person for another slug. |
| 409 | `stale_version` | The service keeps a snapshot of this link with the same version or a higher one. It changed nothing. | Update. | See "Client sequence" below. |
| 429 | `too_many_requests` | The service does not accept more requests from this client now. | Every request. | Reports that the service is unavailable. No retry. |
| 503 | `unavailable` | The service cannot answer now. | Every request. | Reports that the service is unavailable. No retry. |

A client treats a response that is not JSON, a status code that this table does not list, or
an unknown `code` as `unavailable`.

## Client sequence

**Publish.** The client sends the publish request with `version` 1, and stores the link id
and the version with the folder. It shows `url`, and `namedUrl` when it is not empty.

**Update.** For each change of a published folder, the client adds 1 to the stored version,
and sends the whole snapshot with the new version. It stores the new version before it sends
the request. A client that is offline keeps only the latest snapshot of each link, and sends
it when it is online again.

If the service answers `too_many_requests` or `unavailable`, or the client gets no answer, the
client does not send the update again at once. It keeps the snapshot as the latest snapshot
of the link, as it does offline, and sends it later: with the next change of the folder, or
when the app comes to the foreground again. "No retry" in the table of error codes means no
retry at once, and does not mean that the client drops the update.

If the service answers `stale_version`:

1. If the client already sent a higher version of this link, it drops this update. The
   higher version replaces it.
2. Otherwise it reads the link, stores a version above the version that the service
   returned, and sends the update again with it, once.

If the service answers `link_not_found`, the link was unpublished. The client drops the
update and marks the folder as not published.

**Read the counters.** The client reads the link when the person opens the published state
of the folder. It shows `views`, `uniqueViews` and `adds`.

**Unpublish.** The client sends the unpublish request. It keeps the stored link id and
version until the service answers `204 No Content`, and then deletes them. If the request
fails with any other answer, the client keeps the link id and the version, and shows the
folder as published. The person can then unpublish again. To publish the folder again, the
client sends a new publish request with `version` 1.

**Open a link.** The client reads the folder for the address of the link, gets the details
of its titles, and shows them. After the person adds titles, it confirms the add with the
link id of the folder, as "Confirm an add" describes.
