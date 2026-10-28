#!/bin/bash
# CHANGELOG.md에서 특정 버전 칸만 뽑기
#   ./scripts/release-notes.sh 1.0.2
set -euo pipefail
VERSION="${1#v}"
awk -v v="$VERSION" '
  /^## / { if (found) exit; if (index($0, "## " v " ") == 1 || $0 == "## " v) { found = 1; next } }
  found { print }
' "$(dirname "$0")/../CHANGELOG.md" | sed -e '/./,$!d'
