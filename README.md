# Roo Term

A thin SSH host manager and terminal for GNOME — a crossover between
[Guake](https://guake.github.io/) and
[Ásbrú Connection Manager](https://www.asbru-cm.net/).

**Status:** early / usable for day-to-day SSH testing (version **0.1.0**).
Screenshot coming later.

## Features

- **GTK4 + Libadwaita + VTE** — Vala app for GNOME
- **Host tree and tabs** — left host tree, right per-host terminal tabs
- **Per-tab session icons** — each open terminal shows as a small icon on the
  host row; click an icon to jump to that tab (idle / busy / ready / dead)
- **Multi-connection chrome** — one host page with a tab bar; several sessions
  to the same host in one window
- **Guake-style drop-down** — optional GNOME Shell extension with global toggle
  and panel menu
- **Secrets in the keyring** — passwords and SSH key passphrases in libsecret
  (GNOME Keyring / Secret Service), keyed by UUID / key path
- **Own JSON config** — hosts, groups, and forwards under `~/.config/rooterm/`
- **Ásbrú import** — can import from `~/.config/asbru/asbru.yml` on first run
- **Host search** — header search pulldown (`Ctrl+Shift+O`)
- **Port forwards** — local forwards on a connection (add / edit in the dialog)
- **SSH key helpers** — create / install / replace / retire identity keys
- **Local shells** — local PTY tabs alongside SSH hosts
- **sudo after login** — optional `sudo -i` (and LXC-host helpers) on connect

## Secrets and SSH keys

RooTerm encourages **passphrased** SSH identities rather than unprotected private
keys on disk. When you use **Set up SSH key**, the app creates (or reuses)
`~/.ssh/id_ed25519_rooterm` with a passphrase you enter twice, then stores that
passphrase in **libsecret** (GNOME Keyring / Secret Service), keyed by the key
path. Connection passwords go in the keyring the same way (by connection UUID).
`connections.json` never holds secrets.

That keeps the private key encrypted at rest while still letting RooTerm unlock
it for login and `ssh-copy-id` without retyping every time.

Upgrading from a plain **password** login is straightforward: open the
connection, use **Set up SSH key**, and RooTerm creates or reuses the shared
passphrased identity, installs it on the host (using the stored password once),
and switches the connection to key auth. If you already use an identity with
**no** passphrase, Edit connection can offer **Replace with passphrased key**
so you can move to the same pattern.

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

### Install (optional)

Default prefix is `/usr` (needs root):

```bash
sudo meson install -C build
```

That installs `rooterm`, the desktop entry, the app icon, and the GNOME Shell
extension. For day-to-day testing, running `./build/rooterm` from the build
tree is enough.

**Do not** call `valac` directly — always build with Meson/Ninja.

### Packaging / releases

[`CHANGELOG.md`](CHANGELOG.md) is the only changelog to edit. Debian,
RPM, and GitHub release notes are generated from it
(`scripts/release/derive-changelogs.sh`) at package / release time.

GitHub Actions (see [`.github/workflows/release.yml`](.github/workflows/release.yml))
builds three package formats in parallel on `v*` tags (and via workflow
dispatch), then a managing job attaches them to the GitHub Release:

| Artifact | Job | Config |
|----------|-----|--------|
| `.deb` (amd64) | `build-debian` | [`debian/`](debian/) |
| `.rpm` (Fedora 42) | `build-rpm` | [`packaging/rpm/rooterm.spec`](packaging/rpm/rooterm.spec) |
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

## Config paths

- `~/.config/rooterm/connections.json` — hosts, groups, forwards (no secrets)
- `~/.config/asbru/asbru.yml` — read-only import source (Ásbrú)
- `~/.cache/rooterm/` — debug log
- `~/.local/share/rooterm/` — session data (when used)

## Artificial Intelligence Usage

This project was developed with the assistance of artificial intelligence.

- Product design and code design were done by the author
- AI’s main role was writing implementation for review
- Most of the coding was performed by AI
- Code was then reviewed, revised, and approved by the author
- Every line of application code was reviewed and approved by the author
- Limited exceptions apply mainly to the build system

## License

Roo Term is licensed under the **GNU Lesser General Public License**
version 3 or later — see [LICENSE](LICENSE).  
LGPL-3.0 incorporates the GPL; a copy is in [COPYING.GPL](COPYING.GPL).
