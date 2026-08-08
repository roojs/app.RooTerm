# Tab bar strip grows / chip width fights layout (feedback loop)

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed out 2026-08-08

**Started:** 2026-08-08

**Related:**

- **ℹ️** `docs/bugs/done/2026-08-04-FIXED-tabbar-scroll-instead-of-shrink.md` — earlier shrink-to-fit via `tab_width` + `width-request` binding.
- **ℹ️** `src/Host/TabBar.vala` — content-sized chips; Overlay close-fill from **`row.get_width()`**.
- **ℹ️** Background tab close fill (0.9 wishlist) — locked with this close-out.

---

## Problem

- **🔷** Equal-share / `tab_width` + per-chip `width-request` made the strip **grow without bound** (read self width → raise requests → parent grows → repeat).
- **🔷** Close-fill work was unstable while chip math chased a moving `get_width()`.

### Reproduction

1. Open many tabs (or restore) with the old `tab_width` / snapshot path.
2. **Actual:** strip / window width ran away; debug flooded with climbing `bar_w`.
3. **Expected (closed as):** no self-fed width requests; chips content-sized; close fill from chip allocation only.

---

## Resolution

- **✔️** Removed `tab_width`, `size_allocate` override, snapshot/`measured_bar` hacks, and per-row `width-request` binding (GTK4 Box LM never called the override; `tab_width` stayed `-1`).
- **✔️** Baseline: chips size to content; blank spacer still `hexpand` for leftover space inside the strip.
- **✔️** Overlay close-fill re-applied: fill width = `(row.get_width() * left) / total`; pause/cancel; CSS `.host-tab.closing .host-tab-close-fill`.
- **🚫** Do not reintroduce strip budget from **self** `get_width()` + child `width-request` in the same cycle.
- **ℹ️** Equal-share / “strip must not expand past page” redesign left for a later wishlist if many tabs need shrink-to-fit again — not part of this close-out.

---

## Evidence (why the old path failed)

- **✔️** `Gtk.Box` does **not** call an overridden `size_allocate` when a layout manager is installed.
- **✔️** Snapshot / `get_width()` → `width-request` closed a feedback loop (`n * ~8` px growth per frame).
- **✔️** Overlay underlay alone had worked visually before width machinery piled on.

---

## Attempts / changelog

- **💩** Snapshot / idle / `measured_bar` / delta thresholds — symptoms only.
- **✔️** Strip dead width math; content-sized chips.
- **✔️** Overlay fill from chip `row.get_width()`; debug removed on lock-in.
- **✅** 2026-08-08 — user: lock close-fill; close this bug report.
