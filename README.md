# Roo Term

A thin SSH host manager and terminal for GNOME — a crossover between
[Guake](https://guake.github.io/) and
[Ásbrú Connection Manager](https://www.asbru-cm.net/).

Roo Term aims for the quick-access feel of Guake with Ásbrú-style host
organisation, without the heavyweight connection-manager feature set
(no clusters, Expect automation, RDP, and so on).

**Status:** early / usable for day-to-day SSH testing (version **0.1.0**).
Screenshot coming later.

## What it is

- **GTK4** + **Libadwaita** + **VTE** app written in Vala
- Left host tree, right per-host terminal tabs
- Own config under `~/.config/rooterm/` (JSON); can import from Ásbrú’s
  `~/.config/asbru/asbru.yml` on first run
- Passwords and key passphrases in **libsecret** (GNOME Keyring / Secret
  Service) — not Blowfish blobs in the config file

## Special features (vs Guake / Ásbrú)

| Feature | Notes |
| ------- | ----- |
| **Per-tab session icons** | Each open terminal shows as a small icon on the host row; click an icon to jump to that tab. Icons reflect state (idle / busy / ready / dead). |
| **Multi-connection chrome** | One host page with a tab bar; open several sessions to the same host without spawning a new window each time. |
| **Secrets in the keyring** | Connection passwords and SSH key passphrases live in libsecret, keyed by UUID / key path. |
| **Host search** | Header search pulldown (`Ctrl+Shift+O`) filters hosts and opens or focuses them. |
| **Ásbrú import** | Read existing Ásbrú hosts once, then own the config. |
| **Port forwards** | Local forwards on a connection (add / edit in the connection dialog). |
| **Local shells** | Local PTY tabs alongside SSH hosts. |

Intentionally **not** included (yet, and may stay out): Ásbrú clusters,
Expect scripts, multi-protocol sessions, full Guake drop-down overlay
(planned later), packaging / distro packages.

## Dependencies (Debian / Ubuntu)

```bash
sudo apt-get install -y \
  valac meson ninja-build pkg-config \
  libgtk-4-dev libadwaita-1-dev \
  libvte-2.91-gtk4-dev \
  libgee-0.8-dev libgcrypt20-dev \
  libyaml-dev libjson-glib-dev libsecret-1-dev
```

Runtime packages of the same libraries are pulled in by the `-dev` packages.

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

That installs `rooterm`, the desktop entry, and the app icon. For day-to-day
testing, running `./build/rooterm` from the build tree is enough.

**Do not** call `valac` directly — always build with Meson/Ninja.

## Config paths

| Path | Purpose |
| ---- | ------- |
| `~/.config/rooterm/connections.json` | Hosts, groups, forwards (no secrets) |
| `~/.config/asbru/asbru.yml` | Read-only import source (Ásbrú) |
| `~/.cache/rooterm/` | Debug log |
| `~/.local/share/rooterm/` | Session data (when used) |

## License

Roo Term is licensed under the **GNU Lesser General Public License**
version 3 or later — see [LICENSE](LICENSE).  
LGPL-3.0 incorporates the GPL; a copy is in [COPYING.GPL](COPYING.GPL).

## Related projects

- [Guake](https://github.com/Guake/guake) — drop-down terminal for GNOME
- [Ásbrú Connection Manager](https://github.com/asbru-cm/asbru-cm) — full connection manager (Perl)
