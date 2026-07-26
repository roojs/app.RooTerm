# Build Instructions

Canonical build workflow for this project. Written for **AI agents** — **mandatory** for agents building or changing the project. Human contributors may treat this as a helpful guide. See also **`docs/coding-standards.md`**.

**ℹ️** Adapted from OLLMchat for RooTerm. Prefer Meson/Ninja.

## Dependencies

- GTK4, Libadwaita, Vala, Meson, Ninja
- **VTE GTK4** (`libvte-2.91-gtk4-dev`) — preferred system install:

```bash
sudo apt-get install -y libvte-2.91-gtk4-dev libgtk-4-dev libadwaita-1-dev valac meson ninja-build
```

If the system package is missing, a local extract under `.deps/prefix` can be used (see below).

## Building the Project

**IMPORTANT:** Always use `ninja -C build` to build this project. Do NOT use `valac` directly — the build system handles all compilation through Meson/Ninja.

### Standard Build

```bash
meson setup build
ninja -C build
```

### With local VTE GTK4 prefix

```bash
export PKG_CONFIG_PATH=$PWD/.deps/prefix/usr/lib/x86_64-linux-gnu/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
export LD_LIBRARY_PATH=$PWD/.deps/prefix/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
meson setup build   # or: meson setup --reconfigure build
ninja -C build
./build/rooterm --debug
```

Debug log: `~/.cache/rooterm/rooterm.debug.log`

### Rebuilding After Changes

```bash
meson setup --reconfigure build
ninja -C build
```

## Notes

- Never call `valac` directly — always use `ninja -C build`
- `meson.build` adds `--vapidir` for `.deps/prefix/.../vapi` when that directory exists
