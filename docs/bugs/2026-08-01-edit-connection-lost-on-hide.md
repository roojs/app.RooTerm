# Edit Connection lost when drop-down hide/show

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ⏳ Superseded by **`docs/plans/0.12-shell-owns-three-windows.md`** Phase 3 (extension **v36**) — await ✅ verify on X11 + Wayland

**Started:** 2026-08-01

---

## Problem

- **🔷** Edit Connection under drop-down / wrong stacking / lost on hide.
- **🔷** Must work on Wayland.

## Evidence

- **✔️** Sticky `dropDownWin` + `FloatingCount` + width classify were the old hunt (removed).

## Fix applied

- **✔️** Plan 0.12: three long-lived windows; Shell `Register` / `Show` / `Hide` / `Toggle`; Dock only uses stored `mainWin` / `prefsWin` / `connectionWin`.
- **✔️** No `FloatingCount`, width classify, or scavenger scan (extension **v36**).

## Next

1. **🔷** ⏳ Verify on **X11 and Wayland**: Edit Connection survives main Toggle; dialogs stay above main; no `unmanaged cleared slot` on dialog Hide.
2. **🔷** ⏳ Move this file to `docs/bugs/done/` after ✅ on both.
