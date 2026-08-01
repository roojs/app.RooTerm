# FIXED — Toggle key: tooltip stays F12; F1 / F12 do not toggle

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user verified 2026-08-01

**Started:** 2026-08-01

---

## Debug / fix plan (lean)

**Rules for the agent**

- **🚫** Python; **🚫** shell when `Read`/`Grep` on files will do (avoids Cursor Accept spam)
- **🚫** Fix code before Remove/Replace proposal + user approval
- **🔷** Prefer reading `~/.config/rooterm/connections.json` and debug log via file tools
- **🔷** Only ask the user to paste `gsettings` / try a key if file evidence is not enough

### Phase 0 — status

| Check | How | Result |
| ----- | --- | ------ |
| Config on disk | **✔️** `Read` `connections.json` | `"toggle-key" : "F1"` present |
| Debug warnings | **✔️** `Grep` debug log | no `toggle-key save failed` / `toggle binding` hits |
| Tooltip key name | **✔️** code vs JSON | JSON kebab `toggle-key`; JS reads `toggle_key` → always miss → F12 |
| `rooterm --toggle` | **✅** user | works |
| media-keys slot | **✅** user | F1 toggles; Guake custom0 cleared / stolen |

**How to read (remaining)**

| Result | Branch |
| ------ | ------ |
| `rooterm --toggle` does nothing | Fix **`DBus.toggle` / primary** |
| `--toggle` works; F1 still dead | Fix **media-keys slot / conflict** (user pastes `gsettings`) |

---

## Problem

- **🔷** User ran: `rooterm --toggle-key=F1`
- **🔷** Panel tooltip still shows **F12**
- **🔷** **F12** does not toggle
- **🔷** **F1** does not toggle
- **🔷** Expected: config + media-keys shortcut + tooltip all show **F1**, and that key toggles the window globally

### Reproduction

1. Running RooTerm (primary instance / Shell extension active).
2. Run `rooterm --toggle-key=F1` (or `--toggle-key F1`).
3. Hover panel icon — tooltip still says F12.
4. Press F1 / F12 — neither toggles.

---

## Intended design (from code)

Three layers own “the toggle key”:

| Layer | Role | Where |
| ----- | ---- | ----- |
| Config JSON | Source of truth for app + tooltip text | `Config.toggle_key` → `~/.config/rooterm/connections.json` |
| GNOME media-keys | **Global** shortcut → `rooterm --toggle` | `GnomeShell.ensure_toggle_binding` |
| In-app accel | Only when RooTerm window is focused | `MainWindow` → `win.toggle` |
| Extension schema `toggle` | Comment says “panel tooltip only (no wm grab)” | `ensure_toggle_binding` writes `org.gnome.shell.extensions.rooterm` |
| Extension tooltip | Reads **config JSON**, not the schema | `extension.js` hover handler |

`--toggle-key` path (`Application.command_line`):

1. `Config.load()` → set `toggle_key` → `config.save()`
2. `GnomeShell.ensure_toggle_binding(opt_toggle_key)` — create/update custom keybinding slot (`name=RooTerm`, `command=rooterm --toggle`, `binding=<key>`), and set extension schema `toggle`
3. Return 0 (no activate) unless also `--toggle` / `--quit`

Tooltip (`resources/extension/extension.js`):

- Defaults `key = 'F12'`
- On hover, reads `~/.config/rooterm/connections.json` and uses `conf.toggle_key` if present
- On parse/read failure → `console.error` and keeps **F12**

---

## Findings so far (from reading code — not live verification)

### A. Tooltip still F12

- **💩** Most likely: `connections.json` still has no / old `toggle_key`, **or** the hover `JSON.parse` / read failed (extension keeps hardcoded F12).
- **💩** Or: `--toggle-key` never successfully saved (caught → `GLib.warning("toggle-key save failed: …")` only).
- **ℹ️** Tooltip does **not** use the extension gsettings `toggle` key that `ensure_toggle_binding` writes — only the JSON file. Schema write cannot fix the tooltip by itself.
- **ℹ️** Running extension is whatever Shell loaded last; a JSON update should be visible on next hover **without** Shell restart **if** the file on disk is correct. If tooltip stays F12, treat JSON / save failure first.

### B. Neither F1 nor F12 toggles

Global toggle depends on **settings-daemon custom keybinding** firing `rooterm --toggle`, not on the extension grabbing the key.

Possible causes (unranked until evidence):

1. **💩** `ensure_toggle_binding` never ran or failed (same warning as above).
2. **💩** Custom keybinding slot missing / wrong `command` / wrong `binding` / not listed under `custom-keybindings`.
3. **💩** Binding string form wrong for media-keys (e.g. needs `F1` vs something else — Preferences / CLI pass the string through as-is).
4. **💩** Key conflict: another app (historically Guake) still owns F1/F12; settings-daemon may not fire RooTerm’s slot.
5. **💩** `rooterm --toggle` runs but primary D-Bus / `DBus.toggle` no-ops (`block_toggle`, no window, DockMode / ensure races from the restart-dialog work).
6. **ℹ️** In-app `win.toggle` accel alone cannot explain “global” failure — it only works when the window is focused.

### C. Related gaps / footguns in current design

- **ℹ️** `--toggle-key` updates config + gsettings but does **not** refresh an already-open `MainWindow`’s `win.toggle` accel (that is set once at construct from `this.config.toggle_key`). Global path should still work via media-keys → CLI.
- **ℹ️** Dual stores for “display key”: JSON (tooltip) vs extension schema (written, barely used for tooltip). Easy to think schema update fixed the tooltip when it did not.
- **ℹ️** `ensure_toggle_binding` matches an existing slot by `command == "rooterm --toggle"` **or** `name == "RooTerm"`. A stale slot with a different command but name RooTerm would be reused and overwritten — usually fine; a RooTerm-less slot that somehow has the command would also match.

### D. Out of scope / separate (same session noise)

- **ℹ️** Adw.TabBar width: docs only expose `expand-tabs` (full width vs minimum size). No documented per-tab min/max width — tracked separately; not this bug.
- **ℹ️** `--help` killing primary via `OptionContext.parse` `exit(0)` — fix already in tree this session; unrelated except both are CLI → primary remoting.

---

## Evidence

- **✔️** `~/.config/rooterm/connections.json` top level: `"toggle-key" : "F1"` (kebab-case from `Json.gobject_serialize`)
- **✔️** `extension.js` hover uses `conf.toggle_key` (underscore) — property never present → keeps default `'F12'`
- **✔️** `--toggle-key=F1` **did** save; tooltip bug is name mismatch, not a failed CLI save
- **ℹ️** No matching lines in `rooterm.debug.log` for `toggle-key save failed` / `toggle binding`
- **✅** F1 media-keys + `rooterm --toggle` — user verified working

---

## Root cause

### Tooltip stays F12

- **✔️** Extension looks up the wrong JSON key: `toggle_key` vs serialized `toggle-key`.

### F1 / F12 do not toggle

- **✔️** Panel / `rooterm --toggle` works (D-Bus fine).
- **✔️** Guake schema `show-hide` is `'disabled'`; Guake Shell extension absent.
- **✔️** media-keys: **custom0** `guake` / `guake-toggle` / **`F1`** still present; **custom2** `RooTerm` / `rooterm --toggle` / **`F1`**. Same key → Guake slot wins / shadows RooTerm.
- **ℹ️** User: Guake process killed; residual is the **custom keybinding**, not the Guake app schema.

---

## Proposed fix

### Immediate (user)

```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding ''
```

### 2. `ensure_toggle_binding` — clear the same key from other custom slots

**Why:** `--toggle-key=F1` currently writes RooTerm’s slot but leaves Guake (or anything else) still bound to F1.

**Where:** `src/GnomeShell.vala` `ensure_toggle_binding`, after resolving `ours`, before or after setting our binding.

**Depends on:** user approval.

#### Add (after `ours` is known, before writing our slot — or right after setting our binding)
```vala
			foreach (var path in paths) {
				if (path == ours) {
					continue;
				}
				var other = new GLib.Settings.with_path(
					"org.gnome.settings-daemon.plugins.media-keys.custom-keybinding", path
				);
				if (other.get_string("binding") == key) {
					other.set_string("binding", "");
				}
			}
```

- **🔷** Tooltip fix already applied (kebab-case + version 17).
- **🔷** Steal-key: clear other custom slots with the same binding when setting RooTerm’s.

---

## Attempts / changelog

- **ℹ️** 2026-08-01 — bug log from code reading.
- **✔️** 2026-08-01 — confirmed JSON `toggle-key: F1` vs JS `toggle_key` via file Read (no shell).
- **🚫** Avoid shell/`gsettings` in-agent when Cursor Accept spam is an issue; user can paste.
- **✅** 2026-08-01 — user: toggle key working fine; moved to `docs/bugs/done/`.
