#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION="${1:?Version is required}"
OUTPUT_FILE="${2:?Output file is required}"
LAST_TAG="$(git -C "$PROJECT_DIR" describe --tags --match 'v[0-9]*.[0-9]*.[0-9]*' --abbrev=0 2>/dev/null || true)"
[[ -n "$LAST_TAG" ]] && RANGE="$LAST_TAG..HEAD" || RANGE="HEAD"

{
  print -r -- "## DeskBuddy $VERSION"
  print
  print -r -- "Native macOS 26 menu bar control for IDÅSEN and compatible LINAK desks."

  print
  print -r -- "### Changes Since the Previous Release"
  git -C "$PROJECT_DIR" log "$RANGE" --reverse --format='%h%x09%s' | while IFS=$'\t' read -r HASH SUBJECT; do
    [[ -z "$HASH" ]] && continue
    print -r -- "- $SUBJECT (\`$HASH\`)"
  done
} > "$OUTPUT_FILE"
