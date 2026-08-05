# Prefs config_update when main is not running

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✔️ Local save fallback in `Row.send` — await device

**Started:** 2026-08-05

**Related:**

- **ℹ️** `docs/plans/0.15.1-DONE-prefs-process-dbus-cleanup.md` — prefs never wrote config; main `config_update` owned save
- **ℹ️** `docs/bugs/2026-08-04-f1-cold-start-prefs-and-dock.md` — main/prefs process split; `exited(app_id)`
- **ℹ️** `src/Dialog/Row.vala` — `send`

---

## Problem

- **🔷** Prefs process sends chrome changes via `config_update` on `org.roojs.RooTerm.DBus`.
- **🔷** If main is not running, the call fails and nothing is saved — edits are lost.
- **🔷** Prefs already has a `Config` and can `save()` to the same `config.json`.

### Reproduction

1. Quit main (no `org.roojs.RooTerm.DBus`).
2. Run prefs / change a row (opacity, toggle-key, …).
3. **Actual:** warning only; disk unchanged.
4. **Expected:** value written to `~/.config/rooterm/config.json`.

---

## Root cause

- **✔️** `Row.send` caught D-Bus errors and only logged — 0.15.1 forbade prefs `Config.save()` assuming main always owns the write.

---

## Fix applied

- **🔷** On `config_update` failure: parse value onto `this.config`, `set_property`, `config.save()`.
- **✔️** `src/Dialog/Row.vala` — catch path saves locally.

---

## Attempts / changelog

- **🔷** 2026-08-05 — user: if `config_update` cannot reach main, prefs must save locally (trivial).
- **✔️** 2026-08-05 — `Row.send` local apply + save on D-Bus failure.

## Next

- **⏳** **🔷** Device: prefs with main quit → edit opacity → `config.json` updated; with main up → still `config_update` path.
