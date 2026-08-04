# Duplicate Localhost node on every startup

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✔️ applied — awaiting device verify → promote to ✅ / `done/` when confirmed

**Started:** 2026-08-04

---

## Problem

- **🔷** Startup always creates a new Localhost root and appends it to the tree.
- **🔷** Path / local-shell session rows are saved under that Localhost node in `connections.json`.
- **🔷** After a save + relaunch, the tree shows **two** Localhost roots (loaded one + freshly created one).
- **🔷** New local tabs attach to the in-memory `MainWindow.localhost` (the newest empty node); older path children stay under the loaded duplicate.

### Reproduction

1. Run RooTerm once; open a local shell so a `LOCAL_PATH` child is saved under Localhost.
2. Quit and start again.
3. **Expected:** one Localhost root with previous path children.
4. **Actual:** two Localhost roots; paths under the older one.

---

## Evidence

- **✔️** `MainWindow` ctor always created + appended Localhost with no existence check.
- **✔️** Tree load already ran before that append — any saved `LOCAL` root was already in the nest.
- **✔️** `TreeNodes.append` uses `by_uuid.set(uuid, conn)` — duplicate `uuid = "localhost"` overwrites the map while **both** remain in the root list.
- **ℹ️** Related: `docs/bugs/done/2026-08-01-FIXED-tab-password-localhost-tree.md`.

---

## Root cause

- **✔️** Missing `by_uuid.has_key("localhost")` guard before inventing Localhost.

---

## Fix applied

- **✔️** `MainWindow` ctor: if `!by_uuid.has_key("localhost")` → append + save; then `this.localhost = by_uuid.get("localhost")`.
- **🚫** `foreach` / kind-scan; **🚫** auto-merge / delete extras on startup.

## Attempts / changelog

- **🚫** 2026-08-04 — merge/dedupe startup ensure; reverted as too heavy.
- **✔️** 2026-08-04 — has/add/get via `by_uuid` applied.

## Next

- **⏳** **🔷** If two Localhosts already exist in `connections.json`, delete the spare manually (both share uuid so map only keeps one; UI may still show both until cleaned).
- **⏳** **🔷** Verify: relaunch → one Localhost; path children under it; new local tabs use that node. Then move to `docs/bugs/done/` with `FIXED` in the name.
