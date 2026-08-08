# Plank shows RooTerm despite skip_taskbar

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed out 2026-08-07 (Plank restart; icon gone). Reopen if hide/show brings sticky transient back.

**Started:** 2026-08-05

**Related:**

- **ℹ️** `resources/extension/ShellService.js` — hide bracket / `skip_taskbar`
- **ℹ️** `src/DBus.vala` — `skip_taskbar` → `Gdk.X11.Surface.set_skip_taskbar_hint`
- **ℹ️** `docs/bugs/done/2026-08-02-FIXED-wayland-g48-handoff-role-scramble.md` — G48 minimize vs window-list APIs
- **ℹ️** Earlier: `StartupWMClass=rooterm` so Bamf/Plank can match the `.desktop`

---

## Problem

- **🔷** RooTerm must **not** appear on Plank (running / transient icon). Panel indicator only.
- **🔷** On GNOME 48 X11 + Plank, a sticky transient showed even with `_NET_WM_STATE_SKIP_TASKBAR`.

---

## Root cause

- **✔️** Plank adds a `TransientDockItem` on Bamf `UserVisible=true` and does **not** drop it when UserVisible goes false again (only on `app_closed`).
- **✔️** Hide path briefly cleared `skip_taskbar` for minimize → Bamf visibility flash → sticky Plank icon until quit or Plank restart.

---

## Resolution

- **✅** 2026-08-07 — user: restarted Plank; RooTerm icon no longer shown; close bug.
- **ℹ️** Proposed §§1–7 (stop clearing skip in `hide()`, early realize skip, extension bump) were **not** applied. If a hide/show recreates the sticky transient, reopen and apply that plan.

---

## Attempts / changelog

- **ℹ️** 2026-08-05 — investigated Plank + Bamf + xprop; sticky transient with Bamf UserVisible false.
- **ℹ️** 2026-08-05 — Iconic + SKIP_TASKBAR possible on this X11 machine without clearing skip; proposed fix drafted.
- **✅** 2026-08-07 — user: Plank restarted; icon gone; close off.
