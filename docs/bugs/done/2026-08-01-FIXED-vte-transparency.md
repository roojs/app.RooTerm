# FIXED — VTE / drop-down not visually transparent

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user verified 2026-08-01

**Started:** 2026-08-01

**Related:**

- **ℹ️** `docs/plans/0.3-session-states-history-guake.md` — Guake-style semi-transparent drop-down intent
- **ℹ️** `docs/bugs/2026-08-01-preferences-window-and-controls.md` — opacity slider / live apply (prefs UX)

---

## Problem

- **🔷** Terminal background did not look transparent (desktop not visible through VTE).
- **🔷** Tree (left) and bars must stay visually solid.

---

## Root cause

- **✔️** Opaque parents / `.vte-frame` black fill blocked see-through.
- **✔️** VTE `set_colors` background alpha does **not** reliably composite to the desktop; with `clear_background` on, cells stay solid.

---

## Fix (option 0 — single RGBA window)

- **🔷** Window / VTE path CSS transparent; chrome (`.host-pane`, tree, tab bar) stays opaque.
- **🔷** Opacity **100:** VTE `set_clear_background(true)` (solid theme fill).
- **🔷** Opacity **&lt; 100:** VTE `set_clear_background(false)`; dimmed theme colour painted on `.vte-frame` via shared `CssProvider` (`rgba` × opacity%).
- **ℹ️** W1 (multi-window) / W2 (screenshot underlay) not used.

---

## Attempts / changelog

- **ℹ️** 2026-08-01 — explored W1/W2; user chose option 0 (transparent window + opaque chrome).
- **✔️** Cleared opaque `.vte-frame`; removed ScrolledWindow around VTE; `.vte-path` transparent.
- **✔️** Percentage glass via frame `rgba` + `set_clear_background`.
- **✅** 2026-08-01 — user: fixed.
