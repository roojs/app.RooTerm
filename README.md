# Roo Term

A thin SSH host manager and terminal for GNOME — a crossover between
[Guake](https://guake.github.io/) and
[Ásbrú Connection Manager](https://www.asbru-cm.net/).

**Status:** early / usable for day-to-day SSH testing (version **0.1.2**).
Screenshot coming later.

## Install

Packages are published from [roojs/repos](https://github.com/roojs/repos)
at **https://roojs.github.io/repos/**.

### APT (Debian / Ubuntu)

Debian 13 (`trixie`). Ubuntu 25.04 (`plucky`), 25.10 (`questing`), 26.04
(`resolute`). Architectures: `amd64`, `arm64`.

Add the signing key and the sources file, replacing `@suite@` with your
suite from `lsb_release -cs`:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://roojs.github.io/repos/key.gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/roojs.gpg

curl -fsSL https://roojs.github.io/repos/sources \
  | sed "s/@suite@/$(lsb_release -cs)/" \
  | sudo tee /etc/apt/sources.list.d/roojs.sources

sudo apt update
sudo apt install rooterm
```

### DNF (Fedora)

```bash
sudo curl -fsSL https://roojs.github.io/repos/key.gpg \
  -o /etc/pki/rpm-gpg/RPM-GPG-KEY-roojs
sudo curl -fsSL https://roojs.github.io/repos/repo \
  -o /etc/yum.repos.d/roojs.repo
sudo dnf makecache
sudo dnf install rooterm
```

More details (supported suites, package list, and repository layout) are on
the [roojs package repositories](https://roojs.github.io/repos/) page.

To build from source instead, see [BUILD.md](BUILD.md).

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
