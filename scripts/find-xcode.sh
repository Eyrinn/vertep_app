#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Prints the path of the newest installed Xcode with the given major version.
#
#   scripts/find-xcode.sh 27
#
# The script reads the version of each Xcode*.app in /Applications from its Info.plist, so
# the result does not depend on how the app is named. When no Xcode with that major
# version is installed, the script fails and names the missing Xcode. It never returns
# another version. XCODE_SEARCH_DIR replaces /Applications as the directory to search.

set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 <Xcode major version>" >&2
  exit 2
fi

major="$1"
search_dir="${XCODE_SEARCH_DIR:-/Applications}"

matches=()
installed=()

shopt -s nullglob
for app in "$search_dir"/Xcode*.app; do
  # A runner links some versions under a second name. Read each real app once.
  [[ -L "$app" || ! -d "$app" ]] && continue
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ -z "$version" ]] && continue
  installed+=("$version")
  if [[ "${version%%.*}" == "$major" ]]; then
    matches+=("$version"$'\t'"$app")
  fi
done

if [[ ${#matches[@]} -eq 0 ]]; then
  if [[ ${#installed[@]} -eq 0 ]]; then
    found="no Xcode"
  else
    found="Xcode $(printf '%s, ' "${installed[@]}")"
    found="${found%, }"
  fi
  message="Xcode $major is not installed in $search_dir (found: $found). This job builds only with Xcode $major and does not use another version."
  # Standard output carries only the path, so a caller can capture it. On GitHub Actions
  # the annotation goes to standard error, where the runner also reads it.
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::error title=Xcode $major is missing::$message" >&2
  fi
  echo "error: $message" >&2
  exit 1
fi

printf '%s\n' "${matches[@]}" | sort -t $'\t' -k1,1V | tail -n 1 | cut -f 2
