# Account API

This document is the contract between the Vertep app and an account service. With it, a
client can create an account, sign in, keep a session, set a username and delete the
account. A service that follows it works with the app, so a fork can run its own service.

**Scope.** This document describes only what a client sends and what it receives. It does
not describe how a service verifies a passkey or an identity token, how it stores accounts,
keys, challenges or tokens, or which names it refuses. A service can do those things in any
way that gives the answers below.

This document does not cover account recovery by an email code, or how an account adds or
removes passkeys.

## Conventions

The conventions of `docs/search-api.md` apply here too:

- Every request goes over HTTPS.
- Request and response bodies are JSON, encoded as UTF-8. A request with a body sends
  `Content-Type: application/json`. Every response body, including an error, is JSON.
- Binary values are encoded as standard Base64 with padding (RFC 4648, section 4).
- Every path starts with the version prefix `/v1`.
- A client ignores a response field that this document does not name. A service ignores a
  request field that this document does not name.
- "Empty" means the JSON value `null`. A field that can be empty is always present.

Every account response carries `Cache-Control: no-store`. A client does not keep an account
response in a cache.

## Base URL and the attested session

A client sends the account requests to the same base URL as the requests of
`docs/search-api.md`. With the base URL `https://api.example.com`, the current account
request goes to `https://api.example.com/v1/account`.

Every account request needs an attested session: the session token that
`docs/search-api.md` describes in "Attestation and sessions". The client gets the session
token there, and renews it there when the service answers `session_expired`. A client that
cannot open an attested session, for example on the Simulator, cannot send account requests.

## Headers

An account request carries one or two headers:

| Header | Value | Sent with |
|---|---|---|
| `Authorization` | `Bearer <session token>` — the attested session token. | Every account request. |
| `Account-Token` | `<access token>` — the access token of the signed-in account. | Every request that this document marks "Signed in". |

The client does not read the content of the session token, the access token, the refresh
token or the step-up token. Each one is an opaque string.

## Tokens

A sign-in gives the client two tokens:

| Token | Lifetime | What the client does with it |
|---|---|---|
| Access token | 15 minutes | Sends it in `Account-Token` with each "Signed in" request. Keeps it in memory only. |
| Refresh token | 60 days | Sends it to get a new access token and a new refresh token. Stores it in the Keychain, for this device only. |

A refresh token works once. Each refresh returns a new refresh token and ends the old one.
If a refresh token is sent a second time, the service ends every session that came from the
same sign-in, the session of the new refresh token included, and answers
`refresh_token_invalid`. So a client sends one refresh at a time, and stores the new refresh
token before it sends another request.

A step-up token is a fresh confirmation of the person who holds the account. An operation
that needs it, such as account deletion, answers `step_up_required` without it. A step-up
token is valid for 5 minutes and for one operation.

### The session response

A passkey registration, a passkey sign-in, a Sign in with Apple and a refresh each answer
`200 OK` with this body:

```json
{
  "accessToken": "example-access-token-1",
  "accessTokenExpiresIn": 900,
  "refreshToken": "example-refresh-token-1",
  "refreshTokenExpiresIn": 5184000,
  "account": {
    "id": "example-account-id-1",
    "username": null,
    "createdAt": "2026-11-25T10:00:00Z"
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `accessToken` | string | The new access token. |
| `accessTokenExpiresIn` | integer | The seconds until the access token expires. |
| `refreshToken` | string | The new refresh token. It replaces every refresh token that the client stored before. |
| `refreshTokenExpiresIn` | integer | The seconds until the refresh token expires. |
| `account` | object | The account, as "The account object" below describes it. |

### The account object

| Field | Type | Meaning |
|---|---|---|
| `id` | string | The account id. It does not change for the life of the account. |
| `username` | string or empty | The username. Empty until the person sets one. |
| `createdAt` | string | The time the account was created, in RFC 3339 format, in UTC. |

## Passkeys

A passkey creates the account and signs it in. A client creates and uses passkeys with
`ASAuthorizationPlatformPublicKeyCredentialProvider` from Apple's AuthenticationServices
framework. Apple's documentation describes this in "Supporting passkeys".

The relying party id is the domain of the service. For the Vertep service it is
`vertep.app`. A client can use a passkey for a domain only when the app's associated domains
entitlement names it with the `webcredentials` service, as Apple's documentation describes
in "Supporting associated domains".

| Term | Meaning |
|---|---|
| Challenge | Random bytes from the service. The client uses a challenge once, for one passkey registration or one passkey assertion. |
| Credential id | `credentialID` of the registration or the assertion. |
| Client data JSON | `rawClientDataJSON` of the registration or the assertion. |
| Attestation object | `rawAttestationObject` of the registration. |
| Authenticator data | `rawAuthenticatorData` of the assertion. |
| Signature | `signature` of the assertion. |
| User handle | `userID` of the assertion. |

A challenge is valid for one use and for a short time. The service answers
`invalid_challenge` to a challenge that it did not issue, that was already used, or that is
no longer valid.

### Get registration options

```
POST /v1/account/passkey/registration-options
Authorization: Bearer <session token>
```

The request has no body.

Response `200 OK`:

```json
{
  "challenge": "q0n6bU5tE9cXgJxkV4u2Rw==",
  "rpId": "vertep.app",
  "userId": "ZXhhbXBsZS11c2VyLWlkLTEtZXhhbXBsZS11c2VyLWlk",
  "userName": "Vertep"
}
```

| Field | Type | Meaning |
|---|---|---|
| `challenge` | string, Base64 | A new challenge. |
| `rpId` | string | The relying party id. |
| `userId` | string, Base64 | The user id of the new passkey. |
| `userName` | string | The name that the system shows for the passkey. |

Errors: `invalid_request`, `session_expired`, `too_many_requests`, `unavailable`.

### Register a passkey and create the account

The client:

1. Gets registration options.
2. Creates a `ASAuthorizationPlatformPublicKeyCredentialProvider` for `rpId`, and calls
   `createCredentialRegistrationRequest(challenge:name:userID:)` with the decoded
   `challenge`, `userName` and the decoded `userId`. It sets
   `userVerificationPreference` to `.required` and `attestationPreference` to `.none`.
3. Performs the request with `ASAuthorizationController`.
4. Sends the request below with the values of the
   `ASAuthorizationPlatformPublicKeyCredentialRegistration` it got.

```
POST /v1/account/passkey/registration
Authorization: Bearer <session token>
Content-Type: application/json
```

```json
{
  "challenge": "q0n6bU5tE9cXgJxkV4u2Rw==",
  "credentialId": "ZXhhbXBsZS1jcmVkZW50aWFsLWlkLTE=",
  "clientDataJSON": "eyJ0eXBlIjoid2ViYXV0aG4uY3JlYXRlIn0=",
  "attestationObject": "o2NmbXRkbm9uZWdhdHRTdG10oGhhdXRoRGF0YQ=="
}
```

| Field | Type | Meaning |
|---|---|---|
| `challenge` | string, Base64 | The challenge, as the service sent it. |
| `credentialId` | string, Base64 | The credential id. |
| `clientDataJSON` | string, Base64 | The client data JSON. |
| `attestationObject` | string, Base64 | The attestation object. |

The service creates a new account with this passkey and answers with the session response.

Errors: `invalid_request`, `invalid_challenge`, `credential_rejected`, `session_expired`,
`too_many_requests`, `unavailable`.

### Get assertion options

The client gets assertion options to sign in with a passkey, and to get a step-up token with
a passkey.

```
POST /v1/account/passkey/assertion-options
Authorization: Bearer <session token>
```

The request has no body.

Response `200 OK`:

```json
{
  "challenge": "8f2KcLx0mQe1sTn5vYb3Ag==",
  "rpId": "vertep.app"
}
```

| Field | Type | Meaning |
|---|---|---|
| `challenge` | string, Base64 | A new challenge. |
| `rpId` | string | The relying party id. |

Errors: `invalid_request`, `session_expired`, `too_many_requests`, `unavailable`.

### Sign in with a passkey

The client:

1. Gets assertion options.
2. Creates a `ASAuthorizationPlatformPublicKeyCredentialProvider` for `rpId`, and calls
   `createCredentialAssertionRequest(challenge:)` with the decoded `challenge`. It sets
   `userVerificationPreference` to `.required` and gives no allowed credentials, so the
   person picks one of their passkeys for the domain.
3. Performs the request with `ASAuthorizationController`.
4. Sends the request below with the values of the
   `ASAuthorizationPlatformPublicKeyCredentialAssertion` it got.

```
POST /v1/account/passkey/sign-in
Authorization: Bearer <session token>
Content-Type: application/json
```

```json
{
  "challenge": "8f2KcLx0mQe1sTn5vYb3Ag==",
  "credentialId": "ZXhhbXBsZS1jcmVkZW50aWFsLWlkLTE=",
  "clientDataJSON": "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0In0=",
  "authenticatorData": "ZXhhbXBsZQ==",
  "signature": "ZXhhbXBsZS1zaWduYXR1cmU=",
  "userHandle": "ZXhhbXBsZS11c2VyLWlkLTEtZXhhbXBsZS11c2VyLWlk"
}
```

| Field | Type | Meaning |
|---|---|---|
| `challenge` | string, Base64 | The challenge, as the service sent it. |
| `credentialId` | string, Base64 | The credential id. |
| `clientDataJSON` | string, Base64 | The client data JSON. |
| `authenticatorData` | string, Base64 | The authenticator data. |
| `signature` | string, Base64 | The signature. |
| `userHandle` | string, Base64 | The user handle. |

The body above is the "passkey assertion". The step-up request sends the same fields.

The service signs in the account that holds the passkey and answers with the session
response.

Errors: `invalid_request`, `invalid_challenge`, `credential_rejected`, `account_blocked`,
`session_expired`, `too_many_requests`, `unavailable`.

## Sign in with Apple

Sign in with Apple creates an account, or signs in the account that the same Apple ID
created before. A client uses `ASAuthorizationAppleIDProvider` from Apple's
AuthenticationServices framework. Apple's documentation describes this in "Implementing
User Authentication with Sign in with Apple".

### Get a nonce

The client gets a nonce to sign in with Apple, and to get a step-up token with Apple.

```
POST /v1/account/apple/nonce
Authorization: Bearer <session token>
```

The request has no body.

Response `200 OK`:

```json
{
  "nonce": "ZXhhbXBsZS1ub25jZS0x"
}
```

| Field | Type | Meaning |
|---|---|---|
| `nonce` | string | A new nonce. |

A nonce is valid for one use and for a short time. The service answers `invalid_challenge`
to a nonce that it did not issue, that was already used, or that is no longer valid.

Errors: `invalid_request`, `session_expired`, `too_many_requests`, `unavailable`.

### Sign in

The client:

1. Gets a nonce.
2. Calls `ASAuthorizationAppleIDProvider().createRequest()`, sets `nonce` to the nonce
   unchanged, and sets `requestedScopes` to `[.email]`.
3. Performs the request with `ASAuthorizationController`.
4. Sends the request below with the values of the `ASAuthorizationAppleIDCredential` it got.

```
POST /v1/account/apple/sign-in
Authorization: Bearer <session token>
Content-Type: application/json
```

```json
{
  "nonce": "ZXhhbXBsZS1ub25jZS0x",
  "identityToken": "example-identity-token-1",
  "authorizationCode": "example-authorization-code-1"
}
```

| Field | Type | Meaning |
|---|---|---|
| `nonce` | string | The nonce, as the service sent it. |
| `identityToken` | string | `identityToken` of the credential, decoded as UTF-8. |
| `authorizationCode` | string | `authorizationCode` of the credential, decoded as UTF-8. |

The identity token carries the nonce. The service creates an account for an Apple ID it does
not know, or signs in the account that the Apple ID already has, and answers with the
session response.

Errors: `invalid_request`, `invalid_challenge`, `credential_rejected`, `account_blocked`,
`session_expired`, `too_many_requests`, `unavailable`.

## Session

### Refresh the session

The client refreshes the session when it has no valid access token: before a "Signed in"
request, after the access token expired, and after the service answered
`access_token_expired`.

```
POST /v1/account/session/refresh
Authorization: Bearer <session token>
Content-Type: application/json
```

```json
{
  "refreshToken": "example-refresh-token-1"
}
```

| Field | Type | Meaning |
|---|---|---|
| `refreshToken` | string | The stored refresh token. |

The service answers with the session response. The new refresh token replaces the stored
one, and the refresh token in the request no longer works.

Errors: `invalid_request`, `refresh_token_invalid`, `account_blocked`, `session_expired`,
`too_many_requests`, `unavailable`.

### Sign out

```
POST /v1/account/sign-out
Authorization: Bearer <session token>
Content-Type: application/json
```

```json
{
  "refreshToken": "example-refresh-token-2"
}
```

| Field | Type | Meaning |
|---|---|---|
| `refreshToken` | string | The stored refresh token. |

The service ends the session of the refresh token. Response `204 No Content`, with no body.
The service also answers `204 No Content` when the refresh token no longer works.

If the service answers `session_expired`, the client keeps its tokens, opens a new attested
session as `docs/search-api.md` describes, and sends the sign-out again, once. The refresh
token is still needed for that second request. After the last answer, whatever it is, the
client deletes its access token and its refresh token.

Errors: `invalid_request`, `session_expired`, `too_many_requests`, `unavailable`.

## Account

### Get the current account

Signed in.

```
GET /v1/account
Authorization: Bearer <session token>
Account-Token: <access token>
```

Response `200 OK`:

```json
{
  "account": {
    "id": "example-account-id-1",
    "username": "kino",
    "createdAt": "2026-11-25T10:00:00Z"
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `account` | object | The account, as "The account object" describes it. |

Errors: `invalid_request`, `access_token_expired`, `session_expired`, `too_many_requests`,
`unavailable`.

### Set or change the username

Signed in. The same request sets the first username and changes it later.

```
PUT /v1/account/username
Authorization: Bearer <session token>
Account-Token: <access token>
Content-Type: application/json
```

```json
{
  "username": "kino"
}
```

| Field | Type | Meaning |
|---|---|---|
| `username` | string | The new username. |

A username has 3 to 20 characters of `a-z`, `0-9` and `_`. The service changes uppercase
letters `A-Z` to lowercase before it checks the name, so `Kino` and `kino` are the same name.
Two accounts never have the same name.

After a change, the old name stays held for the account for a time, and points to the new
name. During that time the account can take its old name back, and another account gets
`username_taken` for it.

Response `200 OK`: the same body as "Get the current account", with the new username.

Errors: `invalid_request`, `invalid_username`, `username_taken`, `username_reserved`,
`username_not_allowed`, `access_token_expired`, `session_expired`, `too_many_requests`,
`unavailable`.

### Get a step-up token

Signed in. The person confirms again, with a passkey or with Apple, that they hold the
account.

```
POST /v1/account/step-up
Authorization: Bearer <session token>
Account-Token: <access token>
Content-Type: application/json
```

With a passkey, the client gets assertion options and makes an assertion, as in "Sign in
with a passkey", and sends the passkey assertion:

```json
{
  "passkey": {
    "challenge": "8f2KcLx0mQe1sTn5vYb3Ag==",
    "credentialId": "ZXhhbXBsZS1jcmVkZW50aWFsLWlkLTE=",
    "clientDataJSON": "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0In0=",
    "authenticatorData": "ZXhhbXBsZQ==",
    "signature": "ZXhhbXBsZS1zaWduYXR1cmU=",
    "userHandle": "ZXhhbXBsZS11c2VyLWlkLTEtZXhhbXBsZS11c2VyLWlk"
  },
  "apple": null
}
```

With Apple, the client gets a nonce and an Apple ID credential, as in "Sign in with Apple",
and sends:

```json
{
  "passkey": null,
  "apple": {
    "nonce": "ZXhhbXBsZS1ub25jZS0y",
    "identityToken": "example-identity-token-1",
    "authorizationCode": "example-authorization-code-2"
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `passkey` | object or empty | The passkey assertion, with the fields of "Sign in with a passkey". |
| `apple` | object or empty | The fields of "Sign in with Apple". |

Exactly one of `passkey` and `apple` is not empty. The passkey or the Apple ID must belong to
the signed-in account.

Response `200 OK`:

```json
{
  "stepUpToken": "example-step-up-token-1",
  "stepUpTokenExpiresIn": 300
}
```

| Field | Type | Meaning |
|---|---|---|
| `stepUpToken` | string | The step-up token. It is valid for one operation. |
| `stepUpTokenExpiresIn` | integer | The seconds until the step-up token expires. |

Errors: `invalid_request`, `invalid_challenge`, `credential_rejected`,
`access_token_expired`, `session_expired`, `too_many_requests`, `unavailable`.

### Delete the account

Signed in, with a step-up token.

```
POST /v1/account/delete
Authorization: Bearer <session token>
Account-Token: <access token>
Content-Type: application/json
```

```json
{
  "stepUpToken": "example-step-up-token-1"
}
```

| Field | Type | Meaning |
|---|---|---|
| `stepUpToken` | string | A step-up token of this account that no operation used yet. |

The service deletes the account, its passkeys and its sessions. When the account signed in
with Apple, the service also revokes the app's Sign in with Apple authorization for that
Apple ID. The username stays held for a time, and no other account can take it during that
time. Response `204 No Content`, with no body.

After the deletion, the client deletes its access token and its refresh token. The
account's passkeys stay on the person's devices until the person removes them, but the
service answers `credential_rejected` to them.

Errors: `invalid_request`, `step_up_required`, `access_token_expired`, `session_expired`,
`too_many_requests`, `unavailable`.

## Errors

An error response has the body that `docs/search-api.md` describes in "Errors":

```json
{
  "error": {
    "code": "step_up_required",
    "message": "This operation needs a step-up token."
  }
}
```

| Field | Type | Meaning |
|---|---|---|
| `error.code` | string | One of the codes below. The client acts on this field. |
| `error.message` | string | A description for a developer. The client does not show it to a user. |

| Status | Code | Meaning | Returned by | What the client does |
|---|---|---|---|---|
| 400 | `invalid_request` | The request is malformed or a field is missing. | Every request. | Reports that the operation failed. No retry. |
| 400 | `invalid_challenge` | The service did not issue the passkey challenge or the nonce, it was already used, or it is no longer valid. | Passkey registration, passkey sign-in, Sign in with Apple, step-up. | Gets a new challenge or nonce, and asks the person again. |
| 400 | `invalid_username` | The username does not have 3 to 20 characters of `a-z`, `0-9` and `_`. | Set the username. | Tells the person which characters a name can have. No retry. |
| 401 | `session_expired` | The attested session token is missing, has expired, or the service does not know it. | Every request. | Opens a new attested session as `docs/search-api.md` describes, and sends the request again, once. |
| 401 | `access_token_expired` | The access token is missing, has expired, or the service does not know it. | Every "Signed in" request. | Refreshes the session and sends the request again, once. |
| 401 | `refresh_token_invalid` | The refresh token has expired, was already used, was ended by a sign-out, or the service does not know it. | Refresh the session. | Deletes its tokens. The person signs in again. |
| 401 | `credential_rejected` | The service does not accept the passkey, the identity token or the authorization code. For a step-up, also a passkey or an Apple ID of another account. | Passkey registration, passkey sign-in, Sign in with Apple, step-up. | Reports that the sign-in or the confirmation failed. No retry. |
| 403 | `account_blocked` | The account is blocked. The service ended its sessions. | Passkey sign-in, Sign in with Apple, refresh the session. | Deletes its tokens and tells the person that the account is blocked. No retry. |
| 403 | `step_up_required` | The step-up token is missing, has expired, was already used, or belongs to another account. | Delete the account. | Gets a new step-up token, and sends the request again with it, once. |
| 409 | `username_taken` | Another account has this name, or holds it after a change or a deletion. | Set the username. | Asks the person for another name. |
| 409 | `username_reserved` | The service keeps this name for itself. | Set the username. | Asks the person for another name. |
| 409 | `username_not_allowed` | The service does not allow this name. | Set the username. | Asks the person for another name. |
| 429 | `too_many_requests` | The service does not accept more requests from this client now. | Every request. | Reports that the service is unavailable. No retry. |
| 503 | `unavailable` | The service cannot answer now. | Every request. | Reports that the service is unavailable. No retry. |

A client treats a response that is not JSON, a status code that this table does not list, or
an unknown `code` as `unavailable`.

## Client sequence

**Create an account.** The client opens an attested session, registers a passkey, or signs
in with Apple for an Apple ID that has no account. It stores the refresh token and keeps the
access token in memory. The account has no username: the client then sets one.

**Sign in.** The client signs in with a passkey, or with Apple, and stores the tokens as
above.

**Send a "Signed in" request.**

1. If the client has no access token, or the access token expired, it refreshes the session.
2. It sends the request with both headers.
3. If the service answers `session_expired`, the client opens a new attested session and
   sends the request again, once.
4. If the service answers `access_token_expired`, the client refreshes the session and sends
   the request again, once.
5. If a refresh answers `refresh_token_invalid` or `account_blocked`, the client deletes its
   tokens, and the person is signed out.

The client sends one refresh at a time. A request that needs a refresh while another refresh
runs waits for that refresh and uses its tokens.

**Delete the account.** The client gets a step-up token, then sends the deletion with it. If
the deletion answers `step_up_required`, the client gets a new step-up token and sends the
deletion again, once. After the deletion, the client deletes its tokens.
