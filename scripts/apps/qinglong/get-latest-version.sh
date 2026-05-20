#!/bin/bash
set -euo pipefail

INPUT_VERSION="${1:-}"

if [ -n "$INPUT_VERSION" ]; then
  VERSION="$INPUT_VERSION"
else
  # QingLong does not publish GitHub Releases — query Tags API and
  # filter out the `-debian` variant tags (e.g. v2.20.2-debian).
  VERSION=$(curl -sL "https://api.github.com/repos/whyour/qinglong/tags?per_page=30" | \
    jq -r '.[] | .name' | \
    grep -v -- '-debian$' | \
    head -1)
fi

VERSION=$(echo "$VERSION" | sed 's/^v//')

[ -z "$VERSION" ] || [ "$VERSION" = "null" ] && { echo "Failed to resolve version for qinglong" >&2; exit 1; }

echo "VERSION=$VERSION"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$VERSION" >> "$GITHUB_OUTPUT"
fi
