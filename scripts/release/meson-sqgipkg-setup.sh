#!/usr/bin/env bash
# Configure Meson for sqgipkg Linux sysroot / cross builds.
#
# Plucky (or any newer-suite) sysroots ship a newer glib-compile-resources that
# fails on the Noble runner (undefined g_variant_builder_init_static). Force
# host build tools via a Meson native file while still linking against the
# sysroot libraries from PKG_CONFIG_*.
set -euo pipefail

MODE="${1:?mode required: linux}"
BUILD_DIR="${2:?build directory required}"

if [ "$MODE" != linux ]; then
  echo "Unknown mode: $MODE (expected linux)" >&2
  exit 1
fi

export PKG_CONFIG_SYSROOT_DIR="${SQGI_LINUX_SYSROOT:?SQGI_LINUX_SYSROOT is not set}"
export PKG_CONFIG_LIBDIR="${SQGI_LINUX_SYSROOT}/usr/lib/${SQGI_LINUX_TRIPLET}/pkgconfig:${SQGI_LINUX_SYSROOT}/usr/share/pkgconfig"

mkdir -p "$BUILD_DIR"
NATIVE_FILE="$BUILD_DIR/sqgipkg-host-tools.ini"

require_host_tool() {
  local name="$1"
  local path
  path="$(command -v "$name" || true)"
  if [ -z "$path" ] || [ ! -x "$path" ]; then
    echo "Host build tool not found: $name (install libglib2.0-dev)" >&2
    exit 1
  fi
  # Prefer /usr/bin over any sysroot path that may already be on PATH.
  if [ -x "/usr/bin/$name" ]; then
    path="/usr/bin/$name"
  fi
  printf "%s" "$path"
}

GCR="$(require_host_tool glib-compile-resources)"
GCS="$(require_host_tool glib-compile-schemas)"

cat >"$NATIVE_FILE" <<EOF
[binaries]
glib-compile-resources = '${GCR}'
glib-compile-schemas = '${GCS}'
EOF

ARGS=(
  --prefix /usr
  --buildtype=release
  --native-file "$NATIVE_FILE"
)
if [ -n "${SQGI_LINUX_MESON_CROSS_FILE:-}" ]; then
  ARGS+=(--cross-file "$SQGI_LINUX_MESON_CROSS_FILE")
fi

if [ -f "$BUILD_DIR/build.ninja" ]; then
  meson setup "$BUILD_DIR" --reconfigure "${ARGS[@]}"
else
  meson setup "$BUILD_DIR" --wipe "${ARGS[@]}" \
    || meson setup "$BUILD_DIR" "${ARGS[@]}"
fi
