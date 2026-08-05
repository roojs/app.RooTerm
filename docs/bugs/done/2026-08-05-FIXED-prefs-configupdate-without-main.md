# Prefs config_update when main is not running

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed out 2026-08-05

**Started:** 2026-08-05

**Related:**

- **ℹ️** `docs/plans/0.15.1-DONE-prefs-process-dbus-cleanup.md` — prefs never wrote config; main `config_update` owned save
- **ℹ️** `docs/bugs/done/2026-08-04-FIXED-f1-cold-start-prefs-and-dock.md` — main/prefs process split; `exited(app_id)`
- **ℹ️** `src/Dialog/Row.vala` — `send`
- **ℹ️** `src/Dialog/RowScale.vala` — debounced scale send
- **ℹ️** `src/DBus.vala` — `call_async` for Shell show/hide

---

## Problem

- **🔷** Prefs chrome changes via `config_update` on `org.roojs.RooTerm.DBus`.
- **🔷** If main is not running, the call fails and nothing is saved.
- **🔷** Also: open/show deadlock, same-process `call_sync` jam, slider flood.

---

## Fix applied

- **✅** `Row.send`: async `config_update`; on failure apply locally + `config.save()`.
- **✅** `RowScale`: debounce `send` 500ms after last `value_changed`.
- **✅** Prefs open: `present` + async Shell `show` (`call_async`); Close uses async `hide`.
- **✅** Map `register` deferred to Idle (no `call_sync` during map).

---

## Attempts / changelog

- **🔷** 2026-08-05 — user: if `config_update` cannot reach main, prefs must save locally.
- **✔️** `Row.send` local apply + save on D-Bus failure.
- **🔷** Prefs open broken / locked / slider lag — async Shell + async send + 500ms debounce.
- **✅** 2026-08-05 — user: prefs config working; close bug.
