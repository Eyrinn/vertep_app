# Search API

This document is the contract between the Vertep app and a search proxy. A proxy that
follows it works with the app's proxy search, so a fork can run its own proxy.

**Scope.** This document describes only what a client sends and what it receives. It does
not describe how a proxy verifies an attestation or an assertion, how it stores keys,
challenges or sessions, or how it gets its results. A proxy can do those things in any way
that gives the answers below.

## Conventions

- Every request goes over HTTPS.
- Request and response bodies are JSON, encoded as UTF-8. A request with a body sends
  `Content-Type: application/json`. Every response body, including an error, is JSON.
- Binary values are encoded as standard Base64 with padding (RFC 4648, section 4).
- Every path starts with the version prefix `/v1`.
- A client ignores a response field that this document does not name. A proxy ignores a
  request field that this document does not name.
- "Empty" means the JSON value `null`. A field that can be empty is always present.

## Base URL

The app reads the proxy's base URL from its local build configuration, which git does not
track. The base URL is a scheme, a host, an optional port and an optional path prefix, for
example `https://proxy.example.com`. The client appends each path below to the base URL
unchanged: with that base URL, the search request goes to
`https://proxy.example.com/v1/search`.

The app uses the proxy only when a base URL is configured and the device supports App
Attest. The Simulator does not support App Attest, so the app on the Simulator does not use
the proxy.

## Attestation and sessions

The proxy answers a search only for a session, and opens a session only for a key that
Apple's App Attest service has attested. The client uses `DCAppAttestService` from Apple's
DeviceCheck framework.

| Term | Meaning |
|---|---|
| Key | An App Attest key that `DCAppAttestService.generateKey()` creates on the device. |
| Key id | The string that `generateKey()` returns. The client sends it unchanged. It is already Base64. |
| Challenge | Random bytes from the proxy. The client uses a challenge once, for one attestation or one assertion. |
| Client data hash | The SHA-256 hash of the challenge bytes, after Base64 decoding. The client gives this hash to `attestKey` and to `generateAssertion`. |
| Attestation | The attestation object that `DCAppAttestService.attestKey(_:clientDataHash:)` returns. |
| Assertion | The assertion object that `DCAppAttestService.generateAssertion(_:clientDataHash:)` returns. |
| Session token | An opaque string from the proxy. The client sends it with each search and does not read its content. |

Apple's documentation describes the format of an attestation and an assertion, and how a
server validates them: "Establishing your app's integrity" and "Validating apps that connect
to your server".

Debug builds of the app attest in the App Attest development environment. Release builds
attest in the production environment. A proxy that serves debug builds must accept
attestations from the development environment.

### Get a challenge

```
POST /v1/challenge
```

The request has no body.

Response `200 OK`:

```json
{
  "challenge": "q0n6bU5tE9cXgJxkV4u2Rw=="
}
```

| Field | Type | Meaning |
|---|---|---|
| `challenge` | string, Base64 | A new challenge. |

A challenge is valid for one use. The proxy answers `invalid_challenge` to a challenge that
it did not issue, that was already used, or that is no longer valid.

### Attest a key and open a session

The client sends this request when it has no stored key id, or after the proxy rejected the
stored key.

The client:

1. Calls `generateKey()` and stores the key id in the Keychain, for this device only.
2. Gets a challenge.
3. Calls `attestKey(_:clientDataHash:)` with the key id and the client data hash of the
   challenge.
4. Sends the request below.

```
POST /v1/sessions/attest
Content-Type: application/json
```

```json
{
  "keyId": "Zm9yLWV4YW1wbGUtb25seS1rZXktaWQ=",
  "challenge": "q0n6bU5tE9cXgJxkV4u2Rw==",
  "attestation": "o2NmbXRvYXBwbGUtYXBwYXR0ZXN0Z2F0dFN0bXSi..."
}
```

| Field | Type | Meaning |
|---|---|---|
| `keyId` | string | The key id, as `generateKey()` returned it. |
| `challenge` | string, Base64 | The challenge, as the proxy sent it. |
| `attestation` | string, Base64 | The attestation object. |

Response `200 OK`:

```json
{
  "sessionToken": "example-session-token-1"
}
```

| Field | Type | Meaning |
|---|---|---|
| `sessionToken` | string | The token of the new session. |

Errors: `invalid_request`, `invalid_challenge`, `key_rejected`, `too_many_requests`,
`unavailable`.

### Open a session with a stored key

The client sends this request when it has a stored key id and no valid session: at the first
search after the app starts, and after the proxy reported an expired session.

The client:

1. Gets a challenge.
2. Calls `generateAssertion(_:clientDataHash:)` with the stored key id and the client data
   hash of the challenge.
3. Sends the request below.

```
POST /v1/sessions/assert
Content-Type: application/json
```

```json
{
  "keyId": "Zm9yLWV4YW1wbGUtb25seS1rZXktaWQ=",
  "challenge": "8f2KcLx0mQe1sTn5vYb3Ag==",
  "assertion": "omlzaWduYXR1cmVYRzBFAiEA..."
}
```

| Field | Type | Meaning |
|---|---|---|
| `keyId` | string | The stored key id. |
| `challenge` | string, Base64 | The challenge, as the proxy sent it. |
| `assertion` | string, Base64 | The assertion object. |

The response `200 OK` has the same body as the response to an attestation.

Errors: `invalid_request`, `invalid_challenge`, `key_rejected`, `too_many_requests`,
`unavailable`.

## Title search

```
GET /v1/search?q=<query>&lang=<language>
Authorization: Bearer <session token>
```

| Parameter | Meaning |
|---|---|
| `q` | The query, trimmed of leading and trailing whitespace, with at least 2 characters. A character is an extended grapheme cluster, as Swift's `String.count` counts it. The value is percent-encoded. |
| `lang` | The app language: `uk` or `en`. Titles in the response are in this language when one exists. |

The client does not send a query that has fewer than 2 characters after trimming. For such a
query, the search result is empty.

Response `200 OK`:

```json
{
  "results": [
    {
      "id": "tmdb:movie:348",
      "type": "movie",
      "title": "Alien",
      "originalTitle": "Alien",
      "year": 1979,
      "posterPath": "/example-poster-1.jpg",
      "director": "Ridley Scott",
      "creator": null
    },
    {
      "id": "tmdb:tv:1396",
      "type": "tv",
      "title": "Breaking Bad",
      "originalTitle": "Breaking Bad",
      "year": 2008,
      "posterPath": null,
      "director": null,
      "creator": "Vince Gilligan"
    }
  ]
}
```

`results` holds at most 20 results, in the order the client shows them. An empty list means
that nothing matched. Each result has these fields:

| Field | Type | Meaning |
|---|---|---|
| `id` | string | `tmdb:movie:<id>` for a movie or `tmdb:tv:<id>` for a series, where `<id>` is the TMDB id. |
| `type` | string | `movie` or `tv`. It agrees with `id`. |
| `title` | string | The title in the requested language, or the original title when no translation exists. |
| `originalTitle` | string | The title in the original language. |
| `year` | integer or empty | The year of the first release or first air date. |
| `posterPath` | string or empty | TMDB's path of the poster image, for example `/example-poster-1.jpg`. The client builds the image URL from it. |
| `director` | string or empty | For a movie: the director's name, or the names of several directors separated by `, `. Always empty for a series. |
| `creator` | string or empty | For a series: the creator's name, or the names of several creators separated by `, `. Always empty for a movie. |

The results hold only movies and series, never people.

Errors: `invalid_request`, `invalid_query`, `session_expired`, `too_many_requests`,
`unavailable`.

## Errors

An error response has a status code from the table below and this body:

```json
{
  "error": {
    "code": "session_expired",
    "message": "The session has expired."
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `error.code` | string | One of the codes below. The client acts on this field. |
| `error.message` | string | A description for a developer. The client does not show it to a user. |

| Status | Code | Meaning | What the client does |
|---|---|---|---|
| 400 | `invalid_request` | The request is malformed or a field is missing. | Reports that the search failed. No retry. |
| 400 | `invalid_query` | `q` has fewer than 2 characters after trimming, or `lang` is not `uk` or `en`. | Reports that the search failed. No retry. |
| 400 | `invalid_challenge` | The proxy did not issue the challenge, the challenge was already used, or it is no longer valid. | Gets a new challenge and sends the request again, once. |
| 401 | `session_expired` | The session token is missing, has expired, or the proxy does not know it. | Opens a new session and sends the search again, once. |
| 403 | `key_rejected` | The proxy does not accept the key, the attestation or the assertion. | Deletes the stored key id, attests a new key and sends the request again, once. |
| 429 | `too_many_requests` | The proxy does not accept more requests from this client now. | Reports that search is unavailable. No retry. |
| 503 | `unavailable` | The proxy cannot answer now. | Reports that search is unavailable. No retry. |

A client treats a response that is not JSON, a status code that this table does not list, or
an unknown `code` as `unavailable`.

## Client sequence

For one search, the client does these steps. It retries each kind of failure at most once,
so one search sends a bounded number of requests.

1. If the query has fewer than 2 characters after trimming, the result is empty. The client
   sends nothing.
2. If the client has no session token, it opens a session (below).
3. It sends the search with the session token.
4. If the proxy answers `session_expired`, the client discards the token, opens a session,
   and sends the search again. If the second search also fails, the search fails.

To open a session:

1. If a key id is stored, the client opens a session with the stored key. If the proxy
   answers `key_rejected`, the client deletes the stored key id and continues with step 2.
   It does this once per search.
2. If no key id is stored, the client attests a new key and opens a session with it. If the
   proxy answers `key_rejected` to the new key, the search fails.

The client keeps the session token in memory only. A new launch of the app opens a new
session with the stored key.
