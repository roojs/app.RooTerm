# Edit Connection lost when drop-down hide/show

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ✔️ size classify applied — await user verify (extension **v28**)

**Started:** 2026-08-01

---

## Problem

- **🔷** Edit Connection under drop-down / wrong stacking / lost on hide.
- **🔷** Must work on Wayland.

## Evidence

- **✔️** Sticky `dropDownWin` cleared on `unmanaged`; with `FloatingCount=1` both windows hit `raiseFloating`.
- **🔷** Distinguish by size: drop-down ~work-area-wide; dialogs ~520–560px.

## Fix applied

- **✔️** Extension v28: `rect.width > workArea.width / 2` → `dockDropDown`; else if `FloatingCount > 0` → `raiseFloating`. No sticky claim / first-window guess.
- **✔️** Debug `classify` log kept for verify.

## Next

1. **🔷** ⏳ Restart app / reload extension (v28); open Edit Connection; hide/show drop-down; confirm dialog stays centred above.
2. **💩** ⏳ Remove temporary `console.error` / Vala floating_count debug when ✅.
