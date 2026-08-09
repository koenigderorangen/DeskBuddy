#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
LAST_TAG="$(git -C "$PROJECT_DIR" describe --tags --match 'v[0-9]*.[0-9]*.[0-9]*' --abbrev=0 2>/dev/null || true)"

if [[ -n "$LAST_TAG" ]]; then
  CURRENT_VERSION="${LAST_TAG#v}"
  RANGE="$LAST_TAG..HEAD"
else
  CURRENT_VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
  RANGE="HEAD"
fi

if [[ ! "$CURRENT_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Invalid base version: $CURRENT_VERSION" >&2
  exit 1
fi

COMMITS="$(git -C "$PROJECT_DIR" log "$RANGE" --format='%s%n%b%x1e')"
BUMP="none"

if [[ -n "$COMMITS" ]]; then
  if print -r -- "$COMMITS" | grep -Eq '(^|[[:space:]])BREAKING[ -]CHANGE:|^[a-zA-Z]+(\([^)]*\))?!:'; then
    BUMP="major"
  elif print -r -- "$COMMITS" | grep -Eq '^feat(\([^)]*\))?:'; then
    BUMP="minor"
  elif print -r -- "$COMMITS" | grep -Eq '^fix(\([^)]*\))?:'; then
    BUMP="patch"
  fi
fi

IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
case "$BUMP" in
  major) (( MAJOR += 1 )); MINOR=0; PATCH=0 ;;
  minor) (( MINOR += 1 )); PATCH=0 ;;
  patch) (( PATCH += 1 )) ;;
esac

VERSION="$MAJOR.$MINOR.$PATCH"
[[ "$BUMP" == "none" ]] && SHOULD_RELEASE=false || SHOULD_RELEASE=true

print -r -- "current_version=$CURRENT_VERSION"
print -r -- "version=$VERSION"
print -r -- "tag=v$VERSION"
print -r -- "bump=$BUMP"
print -r -- "should_release=$SHOULD_RELEASE"
