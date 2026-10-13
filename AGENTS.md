# Vertep

An iPhone app for picking what to watch. This repository is public and licensed under the Mozilla Public License 2.0 (`LICENSE`).

## Language

Everything in this repository is in English: code, comments, docs, commit messages, branch names, issues, pull requests and review comments. Localization resources (`*.xcstrings`, `*.lproj/`) are the only exception.

## Rules

1. **Write from public sources.** The code here is written from this repository, Apple's documentation and the public parts of the product spec.
2. **The open build is the build.** Every change is done when the app compiles and its tests pass from a plain clone of this repository. An optional `Private/` directory may exist upstream; nothing here may require it, and forks build without it. Code reaches optional features only through protocols declared in `Core`.
3. **No secrets.** API keys, tokens, `.p8` keys, certificates and passwords never enter the repository. Configuration lives in local files listed in `.gitignore`; the repository holds only placeholders and `*.example` / `*.template` files. If a secret reaches a commit, stop and tell a maintainer: it is rotated, because rewriting history does not remove it from forks and caches.
4. **Public behaviour only.** Issues, pull requests, commits, branch names and TODOs describe what the app does, not server-side security details. Report a vulnerability as a private GitHub Security Advisory, never as an issue.
5. **Synthetic test data.** Invented emails, tokens and accounts only; no production logs and no screenshots of real accounts.
6. **License.** Every new source file (`*.swift`, `*.sh`, `*.py`, `*.yml`, `*.yaml`) starts with the MPL-2.0 notice below, unmodified, after a shebang where there is one. Files that cannot carry it (JSON, assets, `.xcstrings`) are covered by `LICENSE`, which is Mozilla's text and is never edited. Dependencies are public packages under licenses compatible with MPL-2.0, pinned to exact versions. Borrowed code keeps its license and attribution.

   ```swift
   // This Source Code Form is subject to the terms of the Mozilla Public
   // License, v. 2.0. If a copy of the MPL was not distributed with this
   // file, You can obtain one at https://mozilla.org/MPL/2.0/.
   ```

7. **When in doubt, ask a maintainer** before writing it down.

## Engineering decisions

- **Platform**: iPhone only, SwiftUI, iOS 18 minimum. Xcode 27, Swift 6 language mode, strict concurrency `complete`.
- **Project generation**: XcodeGen. `project.yml` is the source of truth; the `.xcodeproj` is generated and never committed.
- **Local database**: GRDB 7.x in the `LocalStore` package, behind protocols in `Core` (`Core` never imports GRDB). Migrations are explicit `DatabaseMigrator` steps with a migration test; tests use an in-memory database.
- **Cryptography**: CryptoKit only. Associated data is prefixed `vertep/folder/v1`; the design is to be documented in `docs/crypto.md`.

## Tracker and git

- Work is tracked in this repository's GitHub Issues. Each issue carries exactly one status label: `status: backlog`, `status: ready`, `status: in progress`, `status: in review`, `status: done`.
- An issue's description is not edited; changes and decisions go in comments. Issues are closed only by a merged pull request (`Closes #N` in its body).
- **Branch**: `<type>/<number>-<slug>`, e.g. `feat/12-random-pick`.
- **Commit**: Conventional Commits, `<type>(<scope>): <subject>`, with a `Refs: #N` trailer.
- `main` changes only through pull requests.
