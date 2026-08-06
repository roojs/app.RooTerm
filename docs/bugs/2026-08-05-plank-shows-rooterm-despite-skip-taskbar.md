# Plank shows RooTerm despite skip_taskbar

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ⏳ proposed — await approval

**Started:** 2026-08-05

**Related:**

- **ℹ️** `resources/extension/ShellService.js` — hide bracket clears `skip_taskbar` before minimize
- **ℹ️** `src/DBus.vala` — `skip_taskbar` → `Gdk.X11.Surface.set_skip_taskbar_hint`
- **ℹ️** `docs/bugs/done/2026-08-02-FIXED-wayland-g48-handoff-role-scramble.md` — G48 minimize vs window-list APIs
- **ℹ️** Earlier chat fixed `StartupWMClass=rooterm` so Bamf/Plank **can** match the window to the `.desktop` (needed for pin; also enables transient match)

---

## Problem

- **🔷** RooTerm must **not** appear on Plank (running / transient icon). Panel indicator only.
- **🔷** Same skip-taskbar work that clears GNOME overview / Alt-Tab was assumed to cover Plank; on this machine Plank still shows it.
- **ℹ️** Home machine reported OK; this machine (GNOME 48 X11 + Plank) shows the icon.

---

## Evidence

- **✔️** Main window has `_NET_WM_STATE_SKIP_TASKBAR` + `_NET_WM_STATE_SKIP_PAGER` while shown.
- **✔️** Bamf `UserVisible` for Roo Term = **false**; still `IsRunning` = true.
- **✔️** Plank `GetTransientApplications` still lists `file:///usr/share/applications/org.roojs.rooterm.desktop`.
- **✔️** No pinned `org.roojs.rooterm.dockitem` — this is a **transient** running icon, not Keep-in-Dock.
- **✔️** Plank `Matcher`: apps that open with `!is_user_visible()` stay pending until `user_visible_changed(true)` → then `application_opened` → `TransientDockItem`.
- **✔️** Plank `ApplicationDockItem.handle_user_visible_changed(false)` only emits `app_window_removed`; **removal** of a `TransientDockItem` is on `app_closed` (app quit) — **not** when UserVisible goes false again. So one brief visible flash → sticky Plank icon until quit.
- **✔️** Hide path in `ShellService.hide` **clears** `skip_taskbar` (`false`) so Mutter can minimize, then restores `true` after — that flash is enough for Plank to add a transient and keep it.
- **✔️** On this X11 session, the main window can already be **Iconic** while `SKIP_TASKBAR` remains set (`xdotool windowminimize` / observed state) — the clear-skip bracket is **not** required for minimize here.
- **✔️** `DBus.skip_taskbar` is a no-op on Wayland (no `Gdk.X11.Surface`); G48 Wayland minimize gating is `WaylandLegacyWorkaround` / Meta window-list APIs, not the X11 hint clear.
- **💩** First-map race: `skip_taskbar` is only applied async after Shell `register` / `storeRole`, so the first map may also flash UserVisible before skip is set.

---

## Root cause

- **✔️** Plank treats Bamf `UserVisible=true` as “add transient,” and does **not** drop that transient when UserVisible returns to false.
- **✔️** Our Shell hide path deliberately sets `skip_taskbar(false)` around minimize — that is the Bamf visibility flash on X11.
- **💩** First-map delay before skip may contribute on cold start; hide toggle is enough to reproduce stickiness once matched (`StartupWMClass=rooterm`).

**🚫** Removing `StartupWMClass` is not the fix — it only breaks matching; launch still uses `Exec=`. Would not reliably keep Plank clear and regresses pin/icon identity.

---

## Proposed fix

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

- **🔷** Stop clearing `skip_taskbar` in `hide()`; keep optional Meta `show_in_window_list` before minimize; `finishHide` still restores `skip_taskbar(true)` + `hide_from_window_list` when present.
- **🔷** Set X11 skip hints as soon as the docked main (and preferences) surface is realized, so the first map is never Bamf-visible.
- **🔷** Bump extension `metadata.json` `version` (behavioural JS change).
- **ℹ️** After apply: quit RooTerm or restart Plank once to drop any sticky transient; then toggle must not recreate it.

### 1. `resources/extension/ShellService.js` — `hide()`: do not clear skip_taskbar

**Why:** The `skip_taskbar(false)` D-Bus call makes Bamf `UserVisible=true` long enough for Plank to add a sticky `TransientDockItem`. Minimize works on X11 with skip left on; Wayland does not use the X11 hint; G49 Meta path still gets `show_in_window_list` before minimize; G48 Wayland still uses `WaylandLegacyWorkaround` around `finishHide`.

**Where:** `hide()` — replace the block that starts at the comment `Clear skip_taskbar → idle → minimize` through the closing `);` of that `Gio.DBus.session.call`.

**Depends on:** none

#### Remove

```javascript
        // Clear skip_taskbar → idle → minimize → restore skip (async only).
        Gio.DBus.session.call(
            DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'skip_taskbar',
            new GLib.Variant('(sb)', [role, false]),
            null, Gio.DBusCallFlags.NONE, -1, null,
            function(conn, res) {
                try {
                    Gio.DBus.session.call_finish(res);
                } catch (e) {
                    console.error('rooterm: skip_taskbar false role='
                        + role + ': ' + e);
                }
                if (!self.win[role]) {
                    return;
                }
                if (typeof self.win[role].show_in_window_list === 'function') {
                    self.win[role].show_in_window_list();
                }
                self.win[role].rootermBracketId = GLib.timeout_add(
                    GLib.PRIORITY_DEFAULT, 50, function() {
                        self.finishHide(role, actor);
                        return GLib.SOURCE_REMOVE;
                    }
                );
            }
        );
```

#### Replace with

Leave skip on for Bamf/Plank; only Meta window-list (when present) brackets minimize.

```javascript
        // Do not clear skip_taskbar: Bamf UserVisible flash makes Plank sticky.
        // G49+: show_in_window_list so Mutter allows minimize. G48 X11: minimize
        // with skip left on. G48 Wayland: WaylandLegacyWorkaround wraps finishHide.
        if (typeof this.win[role].show_in_window_list === 'function') {
            this.win[role].show_in_window_list();
        }
        this.win[role].rootermBracketId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT, 50, function() {
                self.finishHide(role, actor);
                return GLib.SOURCE_REMOVE;
            }
        );
```

### 2. `resources/extension/ShellService.js` — `finishHide()` doc comment

**Why:** Comment still says skip was cleared; after §1 it is not.

**Where:** JSDoc immediately above `finishHide(role, actor)`.

**Depends on:** §1

#### Remove

```javascript
    /**
     * After skip_taskbar is cleared: minimize (no WM effect), restore skip,
     * and put main back above when preferences is hidden.
     */
```

#### Replace with

```javascript
    /**
     * Minimize (no WM effect), ensure skip_taskbar / hide_from_window_list,
     * and put main back above when preferences is hidden.
     */
```

### 3. `resources/extension/metadata.json` — bump version

**Why:** Behavioural extension JS change (coding standards).

**Where:** top-level `version` field.

**Depends on:** §1

#### Remove

```json
  "version": 91
```

#### Replace with

```json
  "version": 92
```

### 4. `src/DBus.vala` — `skip_taskbar` doc comment

**Why:** Doc still claims Shell clears skip before minimize.

**Where:** doc comment on `skip_taskbar`.

**Depends on:** §1

#### Remove

```vala
		/**
		 * Set X11 skip-taskbar/pager for a Shell-owned window role.
		 *
		 * Shell clears this briefly before minimize so Mutter allows it, then
		 * sets it again so overview and Alt-Tab stay clear. On GNOME 48, Meta
		 * has no hide_from_window_list for ordinary app windows.
		 *
		 * @param role ``main`` / ``preferences``
		 * @param skip True to hide from task lists
		 */
```

#### Replace with

```vala
		/**
		 * Set X11 skip-taskbar/pager for a Shell-owned window role.
		 *
		 * Keeps overview, Alt-Tab, and Bamf/Plank clear. Do not clear around
		 * minimize on X11 — a UserVisible flash makes Plank keep a sticky
		 * transient icon. On GNOME 48, Meta has no hide_from_window_list for
		 * ordinary app windows (Wayland uses WaylandClient / G49+ Meta APIs).
		 *
		 * @param role ``main`` / ``preferences``
		 * @param skip True to hide from task lists
		 */
```

### 5. `src/MainWindow.vala` — realize: early skip when docked

**Why:** Close first-map race — hints must be set before Bamf sees the mapped window, not only after async Shell `storeRole`.

**Where:** constructor, immediately before the existing `this.map.connect(() => { this.shell.register...` block.

**Depends on:** none (independent of §1; both needed for cold start + toggle)

#### Add — before `this.map.connect` register: set skip on realize when already docked

```vala
			this.realize.connect(() => {
				if (this.is_docked) {
					this.dbus.skip_taskbar("main", true);
				}
			});
```

### 6. `src/MainWindow.vala` — `show_docked()`: set skip when remorphing

**Why:** Cold start may realize before docked; remorph to underbar must set skip without waiting for Shell.

**Where:** end of `show_docked()`, after `set_default_size(...)`.

**Depends on:** §5 (same intent)

#### Remove

```vala
			this.set_default_size(
				this.monitor_geo.width * this.config.width / 100,
				this.monitor_geo.height * this.config.height / 100
			);
		}
```

#### Replace with

Call skip after size; no-op if surface not realized yet (realize handler in §5 covers that).

```vala
			this.set_default_size(
				this.monitor_geo.width * this.config.width / 100,
				this.monitor_geo.height * this.config.height / 100
			);
			this.dbus.skip_taskbar("main", true);
		}
```

### 7. `src/Dialog/Preferences.vala` — realize: early skip

**Why:** Preferences is Shell-owned and must stay off Plank/overview the same way.

**Where:** constructor, immediately before `this.map.connect(() => {` register idle.

**Depends on:** none

#### Add — before preferences `map.connect` register idle:

```vala
			this.realize.connect(() => {
				this.window.dbus.skip_taskbar("preferences", true);
			});
```

---

## Attempts / changelog

- **ℹ️** 2026-08-05 — investigated Plank + Bamf + xprop; confirmed sticky transient with Bamf UserVisible false.
- **ℹ️** 2026-08-05 — confirmed Iconic + SKIP_TASKBAR possible on this X11 machine without clearing skip.
- **ℹ️** 2026-08-05 — rewrote proposed fix with verbatim Remove / Replace with / Add fences.

## Next

- **⏳** **🔷** Approve §§1–7 (or trim §5–7 if Shell-only preferred first).
- **⏳** **🔷** Apply + install extension; quit RooTerm or restart Plank once; verify Plank `GetTransientApplications` has no `org.roojs.rooterm.desktop` after toggle hide/show.
