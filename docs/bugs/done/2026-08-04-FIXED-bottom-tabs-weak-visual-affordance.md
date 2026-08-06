# Bottom tabs: weak visual affordance / hover skips close

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed out 2026-08-06 (happy enough for now)

**Started:** 2026-08-04

**Related:**

- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-tab-password-localhost-tree.md` — dropped `Adw.TabBar` for `Host.TabBar`
- **ℹ️** `src/Host/TabBar.vala` — `.host-tab` / `.host-tab-pick` / `.host-tab-close`
- **ℹ️** `resources/style.css`

---

## Problem

- **🔷** Bottom host tabs do not read as tabs at rest.
- **🔷** Hover should cover title + ×; strip vs chip contrast too weak.
- **🔷** Selected should be **bold**; unselected regular (were all bold).

---

## Fix applied

- **✔️** Pass 1: border + row hover + selected underline; mute button hover.
- **✔️** Pass 2: darker strip; `:has` hover; selected bold.
- **✔️** Pass 3: strip shade 0.90; Vala `hover` class via `EventControllerMotion` (no CSS `:has`); `+` uses `.host-tab-add` chip chrome.

---

## Attempts / changelog

- **ℹ️** 2026-08-04 — investigated; proposed CSS.
- **🔷** 2026-08-05 — apply pass 1–2.
- **🔷** 2026-08-05 — user: `:hover`/`:has` dubious; strip a touch too dark; `+` should match chip colour.
- **✔️** 2026-08-05 — pass 3.
- **✅** 2026-08-06 — user: reasonably happy; close for now.

## Next

- (none — closed)

