# Edit Connection lost when drop-down hide/show

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ✔️ code applied — await user verify (reload extension v22)

**Started:** 2026-08-01

**Related:**

- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-preferences-window-and-controls.md` — same class; Preferences → `Adw.Window` + Shell keep-above (**must** bump extension version)

---

## Problem

- **🔷** Open Edit Connection, then hide/show the main drop-down → Connection editor is gone / unrecoverable.
- **🔷** Same Preferences trick: not a child dialog of the drop-down; own window; keep in front.
- **🔷** Non-modal is fine (Preferences already is).
- **🔷** After standalone window: can still end up **under** the drop-down if Shell still runs old extension JS; opens stuck at the **top** of the screen (annoying).

## Root cause

- **✔️** `Dialog.Connection` was `Adw.Dialog` presented on the main window — tied to that surface’s visibility / stacking.
- **✔️** Keep-above lives in the Shell extension; on-disk JS is ignored until `metadata.json` **version** bumps and `GnomeShell.ensure` reinstalls / user reloads.
- **✔️** GTK parks new decorated windows near the top; Preferences had the same stacking treatment but Connection also needs centre.

## Fix applied

- **✔️** `Dialog.Connection` → standalone `Adw.Window` (`present()` with no parent).
- **✔️** Shell extension treats title `Connection` like `Preferences` for `make_above` / drop-down `unmake_above`.
- **✔️** Extension **v21 → v22** so ensure picks up Connection stacking.
- **✔️** First map of Preferences / Connection: centre on monitor work area (`move_frame`).
- **✔️** Call sites: `TreeMenu`, `MainWindow` sudo-edit → `dlg.present()`.

## Next

1. **🔷** ⏳ Restart app (ensure upgrades to v22) or reload extension; verify stacking + centred Connection.
