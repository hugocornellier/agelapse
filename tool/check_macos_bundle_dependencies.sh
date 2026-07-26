#!/usr/bin/env bash

set -euo pipefail

app_bundle="${1:?usage: check_macos_bundle_dependencies.sh <app-bundle>}"

if [[ ! -d "$app_bundle" ]]; then
  echo "App bundle does not exist: $app_bundle" >&2
  exit 2
fi

invalid_dependency=0

while IFS= read -r -d '' candidate; do
  if ! file -b "$candidate" | grep -q 'Mach-O'; then
    continue
  fi

  while IFS= read -r dependency; do
    case "$dependency" in
      @rpath/* | @loader_path/* | @executable_path/* | /System/Library/* | /usr/lib/*)
        ;;
      *)
        echo "Nonportable dependency in $candidate: $dependency" >&2
        invalid_dependency=1
        ;;
    esac
  done < <(
    otool -l "$candidate" |
      awk '
        /^[[:space:]]*cmd LC_(LOAD|LOAD_WEAK|REEXPORT|LOAD_UPWARD)_DYLIB$/ {
          load_command = 1
          next
        }
        load_command && /^[[:space:]]*name / {
          print $2
          load_command = 0
        }
      '
  )

done < <(find "$app_bundle" -type f -print0)

if [[ "$invalid_dependency" -ne 0 ]]; then
  exit 1
fi

echo "All Mach-O dependencies are bundle-relative or provided by macOS."
