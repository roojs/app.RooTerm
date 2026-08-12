# Edit Connection lost when drop-down hide/show

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ✅ FIXED — plan **`docs/plans/done/0.12-DONE-shell-owns-three-windows.md`** (extension **v37**). Later: Connection off Shell (**0.15** Phase 0); prefs process + ``ConfigUpdate`` (**0.15.1**); extension **v87** drops title-match bind.

**Started:** 2026-08-01

---

## Problem

- **🔷** Edit Connection under drop-down / wrong stacking / lost on hide.
- **🔷** Must work on Wayland.

## Evidence

- **✔️** Sticky `dropDownWin` + `FloatingCount` + width classify were the old hunt (removed).

## Fix applied

- **✔️** Plan 0.12: three long-lived windows; Shell `Register` / `Show` / `Hide` / `Toggle`; Dock only uses stored `mainWin` / `prefsWin` / `connectionWin`.
- **✔️** No `FloatingCount`, width classify, or scavenger scan (extension **v37**).
- **✔️** `Show('main')` raises main then re-raises open dialog so the terminal does not cover Preferences / Connection.

## Next

- **✅** None — closed.
