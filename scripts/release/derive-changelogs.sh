#!/usr/bin/env bash
# Derive debian/changelog and RPM %changelog from CHANGELOG.md (source of truth).
# Usage: scripts/release/derive-changelogs.sh [version] [--notes FILE] [--splice-spec FILE]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"
DEBIAN_OUT="$ROOT/debian/changelog"
RPM_OUT="$ROOT/packaging/rpm/changelog"
CONTROL="$ROOT/debian/control"

version=""
notes_file=""
splice_spec=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		--notes)
			notes_file="$2"
			shift 2
			;;
		--splice-spec)
			splice_spec="$2"
			shift 2
			;;
		-*)
			echo "unknown option: $1" >&2
			exit 1
			;;
		*)
			if [ -n "$version" ]; then
				echo "unexpected argument: $1" >&2
				exit 1
			fi
			version="$1"
			shift
			;;
	esac
done

if [ ! -f "$CHANGELOG" ]; then
	echo "missing $CHANGELOG" >&2
	exit 1
fi

who="$(sed -n 's/^Maintainer:[[:space:]]*//p' "$CONTROL" | head -1)"
if [ -z "$who" ]; then
	who="Alan Knowles <alan@roojs.com>"
fi

src="$(mktemp)"
records="$(mktemp)"
trap 'rm -f "$src" "$records"' EXIT

if [ -n "$version" ] && ! grep -q "^## \[${version}\]" "$CHANGELOG"; then
	sed "s/^## \\[Unreleased\\]/## [${version}] - $(date -u +%Y-%m-%d)/" \
		"$CHANGELOG" > "$src"
else
	cat "$CHANGELOG" > "$src"
fi

ver=""
rel_date=""
catg=""
item=""

flush_item() {
	if [ -z "$ver" ] || [ -z "$item" ]; then
		item=""
		return
	fi
	printf '%s\t%s\t%s\t%s\n' "$ver" "$rel_date" "$catg" "$item" >> "$records"
	item=""
}

: > "$records"
while IFS= read -r line || [ -n "$line" ]; do
	case "$line" in
		'['*']: '*)
			flush_item
			continue
			;;
	esac
	if [[ "$line" =~ ^##\ \[([^\]]+)\](.*)$ ]]; then
		flush_item
		ver="${BASH_REMATCH[1]}"
		rest="${BASH_REMATCH[2]}"
		rel_date=""
		if [[ "$rest" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
			rel_date="${BASH_REMATCH[1]}"
		fi
		catg=""
		continue
	fi
	[ -z "$ver" ] && continue
	if [[ "$line" =~ ^###[[:space:]]+(.+)$ ]]; then
		flush_item
		catg="${BASH_REMATCH[1]}"
		continue
	fi
	if [[ "$line" == -* ]]; then
		flush_item
		item="${line#- }"
		continue
	fi
	if [ -n "$item" ] && [[ "$line" =~ ^[[:space:]]+ ]]; then
		item="$item ${line#"${line%%[![:space:]]*}"}"
		continue
	fi
	flush_item
done < "$src"
flush_item

debian_date() {
	date -u -d "$1" "+%a, %d %b %Y 00:00:00 +0000"
}

rpm_date() {
	date -u -d "$1" "+%a %b %d %Y"
}

today_iso="$(date -u +%Y-%m-%d)"
{
	cur=""
	prev_date=""
	while IFS=$'\t' read -r ver rel_date catg item; do
		[ "$ver" = "Unreleased" ] && continue
		[ -z "$rel_date" ] && rel_date="$today_iso"
		if [ "$ver" != "$cur" ]; then
			if [ -n "$cur" ]; then
				printf '\n -- %s  %s\n\n' "$who" "$(debian_date "$prev_date")"
			fi
			printf '%s (%s-1) unstable; urgency=medium\n\n' "rooterm" "$ver"
			cur="$ver"
			prev_date="$rel_date"
		fi
		if [ -n "$catg" ]; then
			printf '  * %s: %s\n' "$catg" "$item"
		else
			printf '  * %s\n' "$item"
		fi
	done < "$records"
	if [ -n "${cur:-}" ]; then
		printf '\n -- %s  %s\n' "$who" "$(debian_date "$prev_date")"
	fi
} > "$DEBIAN_OUT"

mkdir -p "$(dirname "$RPM_OUT")"
{
	echo "%changelog"
	cur=""
	while IFS=$'\t' read -r ver rel_date catg item; do
		[ "$ver" = "Unreleased" ] && continue
		[ -z "$rel_date" ] && rel_date="$today_iso"
		if [ "$ver" != "$cur" ]; then
			[ -n "$cur" ] && echo
			printf '* %s %s - %s-1\n' "$(rpm_date "$rel_date")" "$who" "$ver"
			cur="$ver"
		fi
		if [ -n "$catg" ]; then
			printf -- '- %s: %s\n' "$catg" "$item"
		else
			printf -- '- %s\n' "$item"
		fi
	done < "$records"
} > "$RPM_OUT"

if [ -n "$splice_spec" ]; then
	tmp_spec="$(mktemp)"
	awk 'BEGIN { p = 1 } /^%changelog/ { p = 0 } p { print }' "$splice_spec" > "$tmp_spec"
	cat "$RPM_OUT" >> "$tmp_spec"
	mv "$tmp_spec" "$splice_spec"
fi

if [ -n "$notes_file" ]; then
	want="$version"
	if [ -z "$want" ]; then
		want="$(head -1 "$records" | cut -f1)"
	fi
	{
		echo "## ${want}"
		echo
		last_cat=""
		found=0
		while IFS=$'\t' read -r ver rel_date catg item; do
			[ "$ver" = "$want" ] || continue
			found=1
			if [ "$catg" != "$last_cat" ]; then
				[ -n "$last_cat" ] && echo
				[ -n "$catg" ] && printf '### %s\n\n' "$catg"
				last_cat="$catg"
			fi
			printf -- '- %s\n' "$item"
		done < "$records"
		if [ "$found" -eq 0 ]; then
			echo "See CHANGELOG.md."
		fi
	} > "$notes_file"
fi

echo "wrote ${DEBIAN_OUT#"$ROOT"/}"
echo "wrote ${RPM_OUT#"$ROOT"/}"
