# Building Roo Term

Build from source with Meson and Ninja. For day-to-day use, install the
`rooterm` package from the [roojs repositories](https://roojs.github.io/repos/)
instead — see [README.md](README.md).

Agents changing this project should also follow [`docs/build-rules.md`](docs/build-rules.md).

## Dependencies (Debian / Ubuntu)

Build (matches `meson.build` minimums: GTK ≥ 4.14, Libadwaita ≥ 1.5,
VTE GTK4 ≥ 0.78):

```bash
sudo apt-get install -y \
  valac meson ninja-build pkg-config desktop-file-utils \
  libgtk-4-dev libadwaita-1-dev \
  libvte-2.91-gtk4-dev \
  libgee-0.8-dev libgcrypt20-dev \
  libyaml-dev libjson-glib-dev libsecret-1-dev
```

Runtime also needs **openssh-client** (`ssh`, `ssh-keygen`). The `-dev`
packages pull in the matching shared libraries.

## Build and run (for testing)

```bash
meson setup build
ninja -C build
./build/rooterm --debug
```

Debug log: `~/.cache/rooterm/rooterm.debug.log`

After code changes:

```bash
meson setup --reconfigure build
ninja -C build
```

**Do not** call `valac` directly — always build with Meson/Ninja.

## Install (optional)

Default prefix is `/usr` (needs root):

```bash
sudo meson install -C build
```

That installs `rooterm`, the desktop entry, and the app icon. The GNOME Shell
extension is installed per-user by the app (`GnomeShell.ensure`), not as a
system copy. For day-to-day testing, running `./build/rooterm` from the build
tree is enough.

## Packaging / releases

[`CHANGELOG.md`](CHANGELOG.md) is the only changelog to edit. Debian
(`debian/changelog`), RPM (`%changelog`), and GitHub release notes are
generated from it by `scripts/release/derive-changelogs.sh` in CI.

To publish a tagged release:

1. Move `[Unreleased]` notes under `## [X.Y.Z] - YYYY-MM-DD`, leave a blank
   `[Unreleased]` heading at the top, and set `meson.build` `version` to
   `X.Y.Z`
2. Commit
3. Run `scripts/release.sh` in a normal terminal (not an agent). It checks
   that meson matches the changelog, tags `vX.Y.Z`, and pushes — GitHub
   Actions then builds packages. If that run was cancelled or failed, commit
   any fix then `scripts/release.sh --retry` (deletes the tag, retags HEAD).

```bash
# after editing CHANGELOG.md + meson.build (and committing):
scripts/release.sh

# after a cancelled or failed CI run for the same version:
scripts/release.sh --retry
```

Local `ninja` builds (git checkout, not a release tarball) show a development
version in About and the debug log: `0.1.2-dev.<git-short>[-dirty]`. A tagged
`vX.Y.Z` commit, or a package build without `.git`, uses `X.Y.Z`.

Agents must not run `scripts/release.sh` (or tag / push a release).

[`.github/workflows/release.yml`](.github/workflows/release.yml) on **`v*`**
tags:

1. Derive `debian/changelog` and RPM `%changelog` from `CHANGELOG.md`
2. Build `.deb`, `.rpm` (Fedora 44), and AppImages
3. Publish GitHub Release assets; release body = notes for that version

Published packages are served from
[roojs/repos](https://roojs.github.io/repos/). `workflow_dispatch` builds
artifacts only (no release unless tagged).

| Artifact | Job | Config |
|----------|-----|--------|
| `.deb` (amd64) | `build-debian` | [`debian/`](debian/) |
| `.rpm` (Fedora 44) | `build-rpm` | [`packaging/rpm/rooterm.spec`](packaging/rpm/rooterm.spec) |
| AppImage (x86_64 + aarch64) | `build-appimage` | [`sqgipkg.json`](sqgipkg.json) |

Local Debian package (regenerates `debian/changelog` from `CHANGELOG.md`):

```bash
./scripts/release/derive-changelogs.sh
dpkg-buildpackage -us -uc -b
```

Local RPM (Fedora / `rpmbuild`):

```bash
./scripts/ci/build-rpm.sh
```

Local AppImages need [sqgi](https://github.com/supercamel/sqgi) / `sqgipkg`
installed, then:

```bash
sqgipkg --target appimage --appimage-arch x86_64
sqgipkg --target appimage --appimage-arch aarch64
```
