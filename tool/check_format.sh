#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
dart_bin="${DART_BIN:-dart}"

# The repository owns and formats its application and plugin sources. Keep the
# byte-for-byte upstream snapshot in third_party out of root formatter churn.
git ls-files -z -- '*.dart' ':(exclude)third_party/**' |
  xargs -0 "$dart_bin" format --output=none --set-exit-if-changed
