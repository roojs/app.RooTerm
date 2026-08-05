# Cold start (F1 / quit): main not under panel (stale Shell slots)

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed out 2026-08-05 (reopen if quit+F1 undocks again)

**Started:** 2026-08-04

**Related:**

- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-docked-ui-not-under-panel.md` — D-Bus name race / dock retry
- **ℹ️** `docs/bugs/done/2026-08-02-FIXED-wayland-g48-handoff-role-scramble.md` — register-skip / handoff
- **ℹ️** `docs/bugs/done/2026-08-05-FIXED-prefs-configupdate-without-main.md` — prefs save / open path
- **ℹ️** `resources/extension/ShellService.js` — `exited` / role slots
- **ℹ️** `resources/extension/WaylandLegacyWorkaround.js` — `register skip already stored`

---

## Problem

- **🔷** Quit RooTerm, press **F1** so a new main process starts → drop-down centred, not under panel.
- **🔷** Further quit/F1 did not recover; GNOME Shell restart did.

---

## Root cause

- **✔️** Shell kept stale `main` / `preferences` Meta slots after quit; new `register` skipped; show/dock hit unmanaged windows.

---

## Fix applied

- **✅** `exited(app_id)` — drop that app’s roles only; `DBus.quit` + name-vanished call it.
- **✅** Lowercase / snake_case D-Bus wire names (`register`, `show`, `hide`, `toggle`, `exited`, …).
- **✅** Extension bumped through **91** (with related prefs open fixes).

---

## Attempts / changelog

- **ℹ️** 2026-08-04 — quit + F1 not under panel; prefs Idle prime.
- **✔️** 2026-08-05 — removed Idle prefs prime; journal `register skip already stored`.
- **🔷** User: `exited` + app id (not blanket Clear); lowercase bus names.
- **✅** 2026-08-05 — user: close as fixed; readdress if it returns.
