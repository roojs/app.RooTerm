# Docked chrome but window not under panel (D-Bus name race)

> Pointer: `docs/bug-fix-process.md`

**Status:** ✅ FIXED — closed 2026-08-01 (no cold-start undocked failure after fix)

**Started:** 2026-08-01

---

## Problem

- **🔷** Startup shows **docked** UI (undecorated drop-down), but window sits in the **middle of the screen** (not under the panel).
- **🔷** No “session needs a restart” dialog.
- **🔷** Panel icon toggle works later.

---

## Evidence (`~/.cache/rooterm/rooterm.debug.log`)

```
15:59:48.425  Config loaded (MainWindow ctor)
15:59:48.731  local spawn          ← window already live
15:59:48.844  Config loaded again (ensure / toggle-key)
15:59:48.845  cleared Guake F1 conflict
15:59:48.867  local pid
15:59:48.872  D-Bus name acquired  ← ~140ms AFTER window up
```

- **✔️** No `is_ready` / `show_docked` / `shown` lines — those paths were never logged (gap).
- **✔️** Order alone is enough: map / `Shown` can run while `org.roojs.RooTerm.DBus` is not on the bus yet.
- **✔️** Extension `isDockMode()` on Get failure returns `false` and skips dock (`console.error` only on failure — not in app debug log).
- **✔️** Extension `watch_name` on appear only sets `indicator.visible = true` — **does not** `scheduleDock()`.

---

## Root cause

- **✔️** Race: first dock attempt(s) happen before the session-bus name exists → `DockMode` Get fails → no move.
- **✔️** When the name later appears, nothing retries docking.

---

## Fix applied

### 1. Extension — dock when D-Bus name appears

**Where:** `resources/extension/extension.js` name-appeared callback — call `scheduleDock()`; bump `metadata.json` version.

### 2. App — emit `shown` after name acquired

**Where:** `src/DBus.vala` — if window already docked/visible when the bus name is acquired, fire `shown()` so the extension can dock.

### 3. App debug

- **✔️** `GLib.debug` on `show_docked`, `shown` paths, and ensure/ready outcome.

---

## After the fix

- **✅** User: no session restart dialog, no cold-start failure to dock — close for now.
- **ℹ️** If it regresses, re-open from this log; watch for name-appear → `scheduleDock` timing in extension + `shown after name acquired` in debug log.
