# Toggle key: tooltip stays F12; F1 / F12 do not toggle

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✔️ tooltip fix applied (kebab-case + version 17); global key still ⏳ user verify

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
| `rooterm --toggle` | **⏳** user | not captured (would need shell Accept) |
| media-keys slot | **⏳** user paste | not captured |

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
- **⏳** Whether F1 media-keys slot exists / whether `rooterm --toggle` works — not captured without shell

---

## Root cause

### Tooltip stays F12

- **✔️** Extension looks up the wrong JSON key: `toggle_key` vs serialized `toggle-key`.

### F1 / F12 do not toggle

- **⏳** Unknown. Config save succeeded; binding/D-Bus still unproven. Separate from tooltip.

---

## Proposed fix

### 1. Tooltip — read the kebab-case key (`extension.js`)

**Why:** Match what `Config.save` actually writes.

**Where:** `resources/extension/extension.js` panel hover handler.

**Depends on:** none. Extension file update may need Shell reload to pick up if not re-copied; user dir copy is what Shell runs — `GnomeShell.ensure` / install copies from GResource on version bump. For a JS-only fix in user extensions dir, either bump `metadata.json` version so ensure reinstalls, or edit the installed copy / reload after install.

#### Remove
```javascript
                if (conf.toggle_key) {
                    key = conf.toggle_key;
                }
```

#### Replace with
```javascript
                if (conf['toggle-key']) {
                    key = conf['toggle-key'];
                }
```

- **🔷** Also bump extension `metadata.json` `version` so `GnomeShell.ensure` reinstalls the fixed `extension.js` into `~/.local/share/gnome-shell/extensions/…` (otherwise Shell keeps the old file).
- **⏳** Global key not working: after tooltip fix, please either run `rooterm --toggle` once and say if the window toggles, or paste the RooTerm custom-keybinding `binding` from Settings → Keyboard — no agent shell required.

---

## Attempts / changelog

- **ℹ️** 2026-08-01 — bug log from code reading.
- **✔️** 2026-08-01 — confirmed JSON `toggle-key: F1` vs JS `toggle_key` via file Read (no shell).
- **🚫** Avoid shell/`gsettings` in-agent when Cursor Accept spam is an issue; user can paste.

---

## Next

1. **🔷** ⏳ Approve tooltip Replace (+ version bump) — apply.
2. **🔷** ⏳ You check: does `rooterm --toggle` toggle? Does F1 work after re-`ensure` / reload?
3. **💩** ⏳ If keys still dead, paste media-keys binding or say `--toggle` failed → next root cause.
