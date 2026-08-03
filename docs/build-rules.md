# Build Instructions

Canonical build workflow for this project. Written for **AI agents** — **mandatory** for agents building or changing the project. Human contributors may treat this as a helpful guide. See also **`docs/coding-standards.md`**.

**ℹ️** Adapted from OLLMchat for RooTerm. Prefer Meson/Ninja.

## Dependencies

```bash
sudo apt-get install -y \
  libvte-2.91-gtk4-0 libvte-2.91-gtk4-dev \
  libgtk-4-dev libadwaita-1-dev libgcrypt20-dev libgee-0.8-dev \
  valac meson ninja-build
```

## Building the Project

**IMPORTANT:** Always use `ninja -C build` to build this project. Do NOT use `valac` directly — the build system handles all compilation through Meson/Ninja.

### Standard Build

```bash
meson setup build
ninja -C build
./build/rooterm --debug
```

Debug log: `~/.cache/rooterm/rooterm.debug.log`

### Rebuilding After Changes

```bash
meson setup --reconfigure build
ninja -C build
```

### Install (desktop entry + icon)

Default prefix is `/usr` (traditional). Needs root:

```bash
meson setup --reconfigure build
ninja -C build
sudo meson install -C build
```

Installs `/usr/bin/rooterm`, `/usr/share/applications/org.roojs.rooterm.desktop`,
and `/usr/share/icons/hicolor/scalable/apps/org.roojs.rooterm.svg`.

**Do not** install the app binary to `~/.local` — use `/usr` only.

### Shell extension

Bundled under `resources/extension/` and installed by the app only
(`GnomeShell.ensure` → `~/.local/share/gnome-shell/extensions/rooterm@roojs.com`
+ enable). Meson does **not** install a system copy under
`/usr/share/gnome-shell/extensions/`.

On GNOME Wayland, a **new** or **upgraded** extension often needs a session
restart once before Shell runs the new `extension.js`.

## Notes

- Never call `valac` directly — always use `ninja -C build`
- In-tree `vapi/` is only for thin bindings not shipped by the distro (`yaml-0.1`, `libgcrypt`)
