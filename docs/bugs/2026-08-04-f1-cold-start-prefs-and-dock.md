# Cold start (F1 / quit): main not under panel (stale Shell slots)

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✔️ `exited(app_id)` + lowercase D-Bus names (v90) — await device quit+F1

**Started:** 2026-08-04

**Related:**

- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-docked-ui-not-under-panel.md` — D-Bus name race / dock retry
- **ℹ️** `docs/bugs/done/2026-08-02-FIXED-wayland-g48-handoff-role-scramble.md` — register-skip / handoff
- **ℹ️** `docs/bugs/2026-08-05-prefs-configupdate-without-main.md` — prefs save when main down
- **ℹ️** `resources/extension/ShellService.js` — `win.main` / `win.preferences` slots
- **ℹ️** `resources/extension/WaylandLegacyWorkaround.js` — `register skip already stored`

---

## Problem

- **🔷** Quit RooTerm, press **F1** (`rooterm --toggle`) so a **new** main process starts.
- **🔷** Main drop-down chrome appears but window sits in the **middle of the screen** (not under panel).
- **🔷** Quit again / wait / F1 again does **not** recover; **GNOME Shell restart** does.
- **ℹ️** Earlier: prefs flash on cold start (Idle `present` + Hide) — Idle prime removed 2026-08-05; dock failure remains.

### Reproduction

1. Quit RooTerm completely (panel / confirm).
2. Press F1 (or `rooterm --toggle` with no primary instance).
3. **Actual:** undecorated main centred on screen; toggle/hide may hit dead Meta windows.
4. **Expected:** main docked under panel; Shell slots bound to the **new** process windows only.

---

## Evidence

- **✔️** Session: X11, GNOME Shell 48.
- **✔️** App debug: `show_docked`, register handle, `redock` — app side thinks dock is fine.
- **✔️** Journal: `register skip already stored` + activate unmanaged after quit+F1.
- **✔️** Workaround skips `register` when `shell.win[role]` is truthy — live window never docks.

---

## Root cause

- **✔️** Shell role cache survives app quit; new `register` is skipped; show/hide/dock target unmanaged Meta windows.
- **✔️** App never told Shell which process exited.

---

## Fix applied

- **🔷** `exited(app_id)` — drop **that** app’s roles only (`org.roojs.rooterm` → `main`; prefs id → `preferences`).
- **🔷** `DBus.quit` calls `exited` with `application_id` before `application.quit()`.
- **🔷** D-Bus name vanished → `exited('org.roojs.rooterm')`.
- **🔷** Wayland handoff: `exited` resets client only when **not** mid-`pending` handoff quit.
- **🔷** D-Bus wire names lowercase / snake_case across Shell + app (`register`, `show`, `hide`, `toggle`, `exited`, `skip_taskbar`, `config_update`, `dock_mode`, `redock`, …).
- **✔️** Extension **90**.

---

## Attempts / changelog

- **ℹ️** 2026-08-04 — user: quit + F1 → not under panel; preferences visible.
- **✔️** 2026-08-05 — removed Idle prefs prime; journal showed stale slots.
- **🔷** 2026-08-05 — user: signal on quit; not Clear; `exited` + app id; lowercase D-Bus names (not PascalCase).
- **✔️** 2026-08-05 — `exited` + quit/name-vanished; renamed bus methods; metadata 90.

## Next

- **⏳** **🔷** Device: quit + F1 → main under panel; journal `exited app_id=org.roojs.rooterm` then `stored role=main` for **new** id. Rebuild app + ensure extension v90 (or Shell reload).
- **⏳** **💩** Prefs app ownership leftover (Ctrl+, still in-process) — out of scope for this dock bug.
