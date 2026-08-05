# Wayland G48 handoff / ensure / extensions-disabled / toggle bounce

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ✅ FIXED — user closed out 2026-08-05

**Started:** 2026-08-02

---

## Problem

- **🔷** Fresh Wayland user (`alan2`): centred / broken chrome; toggle useless; panel died.
- **🔷** Never rely on the **system** extension — user dir only from GResource.
- **🔷** If GNOME Shell **extensions are disabled** for the user, detect at startup and **stay decorated** (do not remorph to underbar / windowless).
- **🔷** Toggle hide then immediately reshow on G48 Wayland (minimize not sticking).

## Evidence

- **✔️** Role scramble after handoff (first run); Register-skip v77 later kept `main` as `/home/alan2`.
- **✔️** ensure treated `/usr/share` as installed → no user copy (fixed: ignore system; meson no longer ships it).
- **✔️** User: Shell extensions were disabled for alan2 → still went windowless; should have stayed normal chrome.
- **✔️** Journal after handoff: repeated `Hide role=main … minimized=false` — slide runs, `minimize()` fails, `finishHide` resets `actor.opacity = 255` / `translation_y = 0` → **hide then reshow**.
- **ℹ️** G48: `Meta.Window` has no `show_in_window_list` / `hide_from_window_list`; only `Meta.WaylandClient` after handoff. ShellService’s `typeof win.show_in_window_list` is false → never clears client hide-from-list before minimize.

## Root cause

- **✔️** ensure / meson system copy (addressed).
- **✔️** Register retry scramble (workaround v77).
- **✔️** **Toggle bounce:** WaylandClient `hide_from_window_list` left on → Mutter refuses minimize → finishHide restores actor → looks like hide+reshow.
- **✔️** **Windowless with extensions off:** `is_ready` / `show_docked` do not check `org.gnome.shell disable-user-extensions` (nor that the Shell bus is actually up).

---

## Proposed fix A — extensions disabled → stay decorated

- **🔷** `src/GnomeShell.vala`: if `disable-user-extensions` is true, `is_ready = false`, alert, do not enable/remorph.
- **🔷** Also require session bus name `org.roojs.RooTerm.Shell` owned before `is_ready` (extension actually running).

### `src/GnomeShell.vala` — add helper used by ctor + ensure

#### Add (inside `GnomeShell` class)

```vala
		/**
		 * True when the user has turned off all GNOME Shell extensions.
		 */
		public bool extensions_disabled()
		{
			return new GLib.Settings("org.gnome.shell").get_boolean("disable-user-extensions");
		}

		/**
		 * True when our Shell extension owns ``org.roojs.RooTerm.Shell``.
		 */
		public bool shell_bus_up()
		{
			try {
				return GLib.Bus.get_sync(GLib.BusType.SESSION, null).call_sync(
					"org.freedesktop.DBus",
					"/org/freedesktop/DBus",
					"org.freedesktop.DBus",
					"NameHasOwner",
					new GLib.Variant("(s)", "org.roojs.RooTerm.Shell"),
					new GLib.VariantType("(b)"),
					GLib.DBusCallFlags.NONE,
					1000,
					null
				).get_child_value(0).get_boolean();
			} catch (GLib.Error e) {
				GLib.debug("Shell bus probe: %s", e.message);
				return false;
			}
		}
```

### ctor — after reading extension info, gate ready

#### Remove

```vala
				this.is_ready = ((int) state_d == 1) && ((int) version_d >= bundled);
```

#### Replace with

```vala
				this.is_ready = !this.extensions_disabled()
					&& ((int) state_d == 1)
					&& ((int) version_d >= bundled)
					&& this.shell_bus_up();
```

### ensure — early exit when extensions globally disabled

#### Add (after toggle binding, before install)

```vala
			if (this.extensions_disabled()) {
				this.is_ready = false;
				this.alert(
					"GNOME Shell extensions are disabled",
					@"Open Settings → Extensions and turn on extensions (and RooTerm), then try again.",
					(owned) done
				);
				return;
			}
```

### ensure — final is_ready assignments also require Shell bus

Wherever `this.is_ready = enabled && …` is set, require `&& this.shell_bus_up()` (or set false and alert “extension not running” if enabled but bus down — Wayland often needs logout after first install).

**Note:** right after `EnableExtension`, bus may not be up yet on Wayland → stay decorated + existing restart alert path; do **not** `show_docked` until bus is up.

---

## Proposed fix B — G48 minimize bracket via WaylandClient (legacy workaround)

- **🔷** Only `WaylandLegacyWorkaround.js` (+ metadata bump **78**).
- **🔷** Wrap `finishHide`: `client.show_in_window_list(win)` before minimize; `hideFromList(win)` after if minimized.
- **🔷** Wrap `Show` (or post-Show): `hideFromList` for owned windows on G48 (Meta API missing).

### `resources/extension/WaylandLegacyWorkaround.js` — in `install`, after storeRole wrap

#### Add

```javascript
        var origFinishHide = shell.finishHide.bind(shell);
        shell.finishHide = function(role, actor) {
            var win = self.shell.win[role];
            if (win && self.client) {
                try {
                    if (self.client.owns_window(win)) {
                        self.client.show_in_window_list(win);
                    }
                } catch (e) {
                    console.error('rooterm: show_in_window_list: ' + e);
                }
            }
            origFinishHide(role, actor);
            if (win && win.minimized) {
                self.hideFromList(win);
            } else if (win) {
                console.error('rooterm: finishHide minimize failed role=' + role
                    + ' id=' + win.get_id());
            }
        };

        var origShow = shell.Show.bind(shell);
        shell.Show = function(role) {
            origShow(role);
            self.hideFromList(self.shell.win[role]);
        };
```

### `resources/extension/metadata.json`

#### Remove

```json
  "version": 77
```

#### Replace with

```json
  "version": 78
```

---

## Attempts / changelog

- **✔️** Workaround v77 Register skip + pending prune; v78 finishHide show_in_window_list + Show hideFromList.
- **✔️** Vala user-only ensure; meson system `install_subdir` removed.
- **✔️** Vala `extensions_disabled` / `shell_bus_up` gate `is_ready`; alert when extensions globally disabled.

- **✅** 2026-08-05 — user: clean up fixed bugs → `done/`.

## Next

- **✅** 2026-08-05 — closed out; moved to `docs/bugs/done/`.
