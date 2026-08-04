# Tree expand shows only a few children until collapse/re-expand

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ⏳ OPEN — urgent; filed only, no investigation yet

**Started:** 2026-08-04

---

## Problem

- **🔷** Expanding a tree row is buggy: often only a **few** children appear.
- **🔷** Collapse the same row, expand again → more (or the full set) of children show up.
- **🔷** Feels intermittent / “habit” of under-filling on first expand.
- **🔷** Urgent — needs a proper root-cause fix soon; this log is the paper trail for now.

## Evidence

- **ℹ️** User report 2026-08-04 — reproduce by expanding; partial list; collapse + expand again fills out.
- **ℹ️** Likely related to recent tree expand save/restore: **`docs/plans/0.14-DONE-tree-expand-save-restore.md`** (`Connection.expanded`, `TreeListModel` `autoexpand = false`, bind on `GROUP` / `lxc_host`). Manual verify for 0.14 was still pending.

## Root cause

- **⏳** Unknown — not investigated yet.

## Proposed fix

- **⏳** None yet — diagnose first (do not guess; no defensive “force expand twice” workaround).

## Attempts / changelog

- (none)

## Next

- **⏳** **🔷** Reproduce with `--debug`; watch tree model / `expanded` / child append timing.
- **⏳** **🔷** Confirm whether 0.14 bind / `autoexpand = false` / restore-on-load races with nest fill.
- **⏳** **🔷** Root-cause fix + approval before code edits.
