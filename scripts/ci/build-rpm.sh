#!/usr/bin/env bash
# Build rooterm RPM from the repository checkout (Fedora / rpmbuild).
# Usage: scripts/ci/build-rpm.sh [version]
# Version defaults to meson project version, or GITHUB_REF_NAME with leading v stripped.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ "$#" -ge 1 ] && [ -n "$1" ]; then
  ver="$1"
elif [ -n "${GITHUB_REF_NAME:-}" ] && [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  ver="${GITHUB_REF_NAME#v}"
else
  ver="$(python3 - <<'PY'
import re
text = open("meson.build", encoding="utf-8").read()
m = re.search(r"project\(\s*'rooterm'.*?version:\s*'([^']+)'", text, re.S)
print(m.group(1) if m else "", end="")
PY
)"
fi
if [ -z "$ver" ]; then
  echo "Could not determine package version" >&2
  exit 1
fi

echo "Building rooterm RPM version ${ver}"

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_root dnf -y install \
  rpm-build rpmdevtools \
  meson ninja-build gcc pkgconf-pkg-config vala desktop-file-utils \
  gtk4-devel libadwaita-devel vte291-gtk4-devel \
  libgee-devel libgcrypt-devel libyaml-devel \
  json-glib-devel libsecret-devel \
  openssh-clients

TOPDIR="${ROOT}/.rpmbuild"
rm -rf "$TOPDIR"
mkdir -p "$TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Working-tree tarball (excludes VCS and local build outputs).
tar --exclude='./.git' \
  --exclude='./.rpmbuild' \
  --exclude='./.sqgipkg' \
  --exclude='./.ci-cache' \
  --exclude='./build' \
  --exclude='./build-linux-*' \
  --exclude='./dist-linux-*' \
  --exclude='./artifacts' \
  --transform "s|^\\./|rooterm-${ver}/|" \
  -czf "${TOPDIR}/SOURCES/rooterm-${ver}.tar.gz" \
  .

cp packaging/rpm/rooterm.spec "${TOPDIR}/SPECS/rooterm.spec"

rpmbuild -ba \
  --define "_topdir ${TOPDIR}" \
  --define "rooterm_version ${ver}" \
  "${TOPDIR}/SPECS/rooterm.spec"

mkdir -p "${ROOT}/artifacts"
find "${TOPDIR}/RPMS" -type f -name '*.rpm' ! -name '*.src.rpm' -exec cp -v {} "${ROOT}/artifacts/" \;
ls -lh "${ROOT}/artifacts"
