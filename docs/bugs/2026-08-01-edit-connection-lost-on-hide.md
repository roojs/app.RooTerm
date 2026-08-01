# Edit Connection lost when drop-down hide/show

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ✔️ code applied — await user verify (extension **v26** + Shell reload)

**Started:** 2026-08-01

**Related:**

- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-preferences-window-and-controls.md`

---

## Problem

- **🔷** Edit Connection under drop-down / stuck at top / lost on hide.
- **🔷** Classic min/max/close on Connection and Preferences (want Cancel + Save).
- **🔷** Must work on **Wayland** (not X11-only WM role).

## Root cause

- **✔️** Extension used title / decorated; `fill()` retitled to Edit/Add connection → docked as drop-down.
- **✔️** `WM_WINDOW_ROLE` is X11-only (GTK4 has no `set_role`) — not shippable for Wayland.

## Fix applied

- **✔️** D-Bus ``FloatingCount``: Preferences / Connection `map`++ / `unmap`--.
- **✔️** Extension v26: sticky first drop-down; ``dockWindow`` / ``raiseFloating`` / ``dockDropDown``; ``FloatingCount`` for dialogs.
- **✔️** Removed X11 `WM_WINDOW_ROLE` + `gtk4-x11` dep.
- **✔️** Connection + Preferences: header Cancel/Save only; Preferences Cancel reverts snapshot.

## Next

1. **🔷** ⏳ Restart app (ensure → v26) or reload extension; verify on X11; Wayland when available.
