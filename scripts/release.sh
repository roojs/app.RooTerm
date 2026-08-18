#!/usr/bin/env bash
# Verify the tree is ready, then tag + push. That is all.
#
# 1. Read latest ## [X.Y.Z] from CHANGELOG.md (not [Unreleased])
# 2. Exit if tag vX.Y.Z already exists (local or origin)
# 3. Verify: Unreleased is empty, clean tree, non-empty notes, meson version matches
# 4. git tag -a + git push (branch + tag) → GitHub Actions builds packages
#
# Does NOT rewrite debian/changelog, RPM %changelog, or build packages.
# GitHub Actions does that from CHANGELOG.md after the tag lands
# (scripts/release/derive-changelogs.sh).
#
# AGENTS ARE BANNED from running this script. Do not tag, push, or release
# on the user's behalf. Do not unset CURSOR_AGENT, spoof the environment,
# invoke git tag/push directly, or otherwise work around this guard.
# Only the human runs scripts/release.sh in a normal terminal.
set -euo pipefail

if [[ "${CURSOR_AGENT:-}" == "1" ]]; then
	cat >&2 <<'EOF'
error: agents are banned from running scripts/release.sh.

Do not work around this (unset CURSOR_AGENT, fake the env, call git tag/push
yourself, etc.). The human must run scripts/release.sh in a normal terminal.
EOF
	exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"

if [[ ! -f CHANGELOG.md ]]; then
	echo "error: missing CHANGELOG.md" >&2
	exit 1
fi

if awk '
	BEGIN { u=0 }
	/^## \[Unreleased\]/ { u=1; next }
	u && /^## / { exit }
	u && /^- / { found=1; exit }
	END { exit found ? 0 : 1 }
' CHANGELOG.md; then
	echo "error: [Unreleased] still has notes — move them under ## [X.Y.Z] - YYYY-MM-DD first" >&2
	exit 1
fi

header="$(grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1 || true)"
if [[ -z "${header}" ]]; then
	echo "error: no ## [X.Y.Z] heading in CHANGELOG.md" >&2
	exit 1
fi
ver="$(sed -E 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/' <<<"${header}")"
tag="v${ver}"

notes="$(awk -v ver="${ver}" '
	BEGIN { take=0 }
	$0 ~ "^## \\[" ver "\\]" {
		take=1
		next
	}
	take && /^## / { exit }
	take { print }
' CHANGELOG.md)"

echo "CHANGELOG.md latest: ${ver}"
echo "Tag: ${tag}"
echo "---- notes ----"
echo "${notes}"
echo "---------------"

if [[ -z "${notes//[[:space:]]/}" ]]; then
	echo "error: empty notes for ${ver} — fill CHANGELOG.md first" >&2
	exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
	echo "error: working tree not clean — commit or stash before releasing" >&2
	git status --short >&2
	exit 1
fi

meson_ver="$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" meson.build | head -1)"
if [[ "${meson_ver}" != "${ver}" ]]; then
	echo "error: meson.build version '${meson_ver}' != CHANGELOG.md '${ver}'" >&2
	exit 1
fi

git fetch --tags origin 2>/dev/null || true

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
	echo "Tag ${tag} already exists locally — nothing to do."
	exit 0
fi

if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
	echo "Tag ${tag} already exists on origin — nothing to do."
	exit 0
fi

echo "Creating annotated tag ${tag}..."
git tag -a "${tag}" -m "${tag}"

branch="$(git rev-parse --abbrev-ref HEAD)"
echo "Pushing ${branch} and ${tag} to origin..."
git push -u origin "${branch}"
git push origin "${tag}"

echo "Released ${tag}. GitHub Actions will derive debian/changelog and RPM %changelog, build .deb/.rpm/AppImage, and publish notes from CHANGELOG.md."
