#!/usr/bin/env bash
# Install VTE GTK4 ≥ 0.78 on Ubuntu 24.04 (Noble) from the Plucky archive.
# Noble only ships 0.76 (no termprop APIs). Plucky has 0.80.x.
#
# Adds Plucky as a low-priority apt source and installs only the VTE stack
# (plus libicu76) from it. Fine for a fixed CI image; not for general desktops.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive

. /etc/os-release
if [ "${VERSION_CODENAME:-}" != "noble" ]; then
  # Newer Ubuntu already has a new enough VTE in the default archive.
  apt-get install -y --no-install-recommends libvte-2.91-gtk4-dev
  pkg-config --modversion vte-2.91-gtk4
  exit 0
fi

LIST=/etc/apt/sources.list.d/plucky-vte.list
PREF=/etc/apt/preferences.d/plucky-vte

cat >"$LIST" <<'EOF'
deb http://archive.ubuntu.com/ubuntu plucky main universe
deb http://archive.ubuntu.com/ubuntu plucky-updates main universe
EOF

# Prefer Noble for everything; only pull listed packages from Plucky.
cat >"$PREF" <<'EOF'
Package: *
Pin: release n=plucky
Pin-Priority: 100

Package: libvte-2.91-* gir1.2-vte-* libicu76
Pin: release n=plucky
Pin-Priority: 990
EOF

apt-get update
apt-get install -y --no-install-recommends \
  libicu76 \
  libvte-2.91-common \
  libvte-2.91-gtk4-0 \
  gir1.2-vte-3.91 \
  libvte-2.91-gtk4-dev

ver="$(pkg-config --modversion vte-2.91-gtk4)"
echo "Installed vte-2.91-gtk4 ${ver}"
# termprop landed in 0.78
dpkg --compare-versions "$ver" ge 0.78
