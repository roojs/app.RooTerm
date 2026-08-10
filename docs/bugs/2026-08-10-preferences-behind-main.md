# Preferences: separate process only

**Status:** ⏳ design (open path not implemented this way yet)

## One rule

The **only** way Preferences appears is:

```text
rooterm --preferences
```

That starts (or activates) app id **`org.roojs.rooterm.preferences`**.  
**That process** creates the Preferences window, Registers it with Shell, and asks Shell to Show it.

Main (`org.roojs.rooterm`) **never** creates or presents a Preferences window.

## Who opens it

| From | What happens |
| ---- | ------------ |
| Main (Ctrl+, / menu) | Spawns `rooterm --preferences` (CLI). No D-Bus “show preferences”. |
| Shell panel | Same: run `rooterm --preferences`. |
| Already running prefs | Second `--preferences` hits the existing prefs app → it Shows again. |

Delete main’s D-Bus `preferences()` method. It must not exist.

## What the prefs process does

1. Start with `--preferences` → application id `org.roojs.rooterm.preferences`.
2. Create **only** the Preferences window (no MainWindow).
3. On map: Shell **`register('preferences', handle)`**.
4. Then Shell **`show('preferences')`** → centre / `make_above` / raise above main.
5. Close → Shell **`hide('preferences')`** (minimize; process can stay held).
6. Rows change chrome via main’s existing **`config_update`** on `org.roojs.RooTerm.DBus` (main still owns config apply/save).

## What main does / does not do

- **Does:** spawn `rooterm --preferences` when the user asks for prefs.
- **Does:** keep owning `org.roojs.RooTerm.DBus` (`toggle`, `quit`, `config_update`, `skip_taskbar` for **main**, …).
- **Does not:** hold `preferences_editor`, Register prefs, or present prefs.
- **Does not:** clear the Shell **preferences** slot on main `exited` — that slot belongs to the prefs process (`exited` for `org.roojs.rooterm.preferences`).

## Shell stacking

```text
prefs process --register--> Shell slot preferences
prefs process --show------> Shell make_above + raise preferences (main yields)
```

Main’s underbar can stay visible underneath; Shell already knows to put **preferences** above **main** when that slot is shown.

## Not this

- Main D-Bus method that presents an in-process prefs window.
- Prefs as a child/transient of MainWindow.
- Opening prefs by any path other than `--preferences`.
