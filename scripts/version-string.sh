#!/usr/bin/env bash
# Print the runtime version for this build (stdout only).
# Tagged vX.Y.Z commit: X.Y.Z
# Other git trees: <latest-tag>-dev.<short-hash>[-dirty]
# No git (package tarball): meson project version (arg 1)
set -euo pipefail

meson_ver="$1"
root="$2"
cd "$root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "$meson_ver"
	exit 0
fi

rev="$(git rev-parse --short HEAD)"
dirty=""
if ! git diff --quiet HEAD 2>/dev/null; then
	dirty="-dirty"
fi

tag="$(git describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null || true)"
if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "${tag#v}${dirty}"
	exit 0
fi

base="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
if [[ "$base" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	base="${base#v}"
else
	base="$meson_ver"
fi
echo "${base}-dev.${rev}${dirty}"
