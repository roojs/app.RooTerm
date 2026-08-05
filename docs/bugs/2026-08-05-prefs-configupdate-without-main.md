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
1
---

## Attempts / changelog

- **🔷** 2026-08-05 — user: if `config_update` cannot reach main, prefs must save locally (trivial).
- **✔️** 2026-08-05 — `Row.send` local apply + save on D-Bus failure.
- **🔷** 2026-08-05 — user: Preferences startup broken after Idle prime removal.
- **✔️** Evidence: journal `show missing role=preferences` — `preferences()` called Shell show without `present`/register.
- **✔️** Fix: `DBus.preferences` present + idle register + show; Actions uses `dbus.preferences()`; drop storeRole auto-hide prefs and Bus.watch hide (v91).
- **🔷** 2026-08-05 — user: prefs locked on screen, app not responding (call_sync show after present deadlocks with Shell `skip_taskbar`).
- **✔️** Fix: async Shell `show`/`hide` for prefs; defer map `register` to Idle. Killed stuck process.
- **🔷** 2026-08-05 — user: config send jams (same-process `call_sync` `config_update`).
- **✔️** `Row.send` uses async `call.begin` / local save on failure.
- **🔷** 2026-08-05 — user: slider locks prefs UI; no debounce — flood of sends.
- **✔️** `RowScale` debounces `send` 500ms after last `value_changed`.

## Next

- **⏳** **🔷** Device: drag width/height/opacity — scale stays smooth; one update after release/settle.
- **⏳** **🔷** Device: Ctrl+, opens prefs; Close hides.
- **⏳** **🔷** Device: prefs with main quit → edit opacity → `config.json` updated; with main up → still `config_update` path.
