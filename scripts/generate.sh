#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Generates Vertep.xcodeproj from project.yml with XcodeGen.
#
# The optional Private/ project is included only when Private/Package.swift exists.
# Without it, the generated project is the open build and has no reference to Private/.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f Private/Package.swift ]]; then
  export VERTEP_PRO=YES
  echo "Generating Vertep.xcodeproj with the optional Private/ project."
else
  export VERTEP_PRO=NO
  echo "Generating Vertep.xcodeproj for the open build (no Private/Package.swift)."
fi

# .mise.toml pins the XcodeGen version. mise installs and runs that version; an XcodeGen on
# the PATH is used only when mise is not installed.
pinned="$(sed -n 's/^xcodegen *= *"\(.*\)"/\1/p' .mise.toml)"

if command -v mise >/dev/null 2>&1; then
  exec mise exec -- xcodegen generate --spec project.yml
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: XcodeGen $pinned is not installed. Install mise (https://mise.jdx.dev)," >&2
  echo "       or install XcodeGen $pinned and put it on the PATH." >&2
  exit 1
fi

installed="$(xcodegen --version | sed 's/^Version: *//')"
if [[ "$installed" != "$pinned" ]]; then
  echo "warning: XcodeGen $installed is on the PATH, and .mise.toml pins $pinned." >&2
fi

exec xcodegen generate --spec project.yml
