# Preferences: separate window + controls (key capture, sliders, live apply)

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user verified 2026-08-01

**Started:** 2026-08-01

**Related:**

- **ℹ️** `docs/plans/0.8-DONE-preferences.md` — first prefs dialog (spin + entry; apply on close; `PreferencesDialog`)
- **ℹ️** `docs/bugs/2026-08-01-toggle-key-tooltip-and-binding.md` — global toggle binding / F1
- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-vte-transparency.md` — VTE glass (✅)

---

## Tracking index

| # | Topic | Status |
| - | ----- | ------ |
| A | Prefs dialog steals clicks when drop-down is hidden — want separate window | ✅ |
| B | Toggle key capture button; opacity/height/width sliders + live apply | ✅ |
| C | Prefs window stacks under always-on-top drop-down / may get docked | ✅ |

**🚫** Do not change placement control (ComboRow is fine). **🚫** Do not fold VTE compositing into this log.

---

## A — Prefs steals clicks / should be a separate window

### Problem

- **🔷** With Preferences open, hide the drop-down (toggle) → other apps lose click context (surface / grab still eating input).
- **🔷** Want Preferences as a **separate window**, not a dialog of the main drop-down — if the stack allows it.

### Root cause

- **✔️** Preferences was a **modal/sheet dialog owned by** the Guake-style main window. Hiding that window while the dialog is up left a broken input / focus situation for the rest of the desktop.

### Fix

- **✅** **A2** — `Dialog.Preferences` is a custom `Adw.Window` hosting `Adw.PreferencesPage` (not `PreferencesDialog` / `PreferencesWindow`).
- **✅** `present()` with no parent; `DBus.preferences()` no longer forces the drop-down visible.

---

## B — Key capture button + sliders + live apply

### Problem

- **🔷** Toggle key should be a capture button (not a text entry); must swallow the key (no toggle while capturing).
- **🔷** Opacity / height / width as sliders with live drop-down update.
- **🔷** Prefs writes `config`; MainWindow notify owns geometry apply.

### Fix

- **✅** Toggle key: button + `EventControllerKey` CAPTURE; `block_toggle` while capturing; Escape cancels.
- **✅** Opacity / height / width: `Gtk.Scale` → `config` on `value_changed`.
- **✅** Placement ComboRow writes `config.placement` on change.
- **✅** `MainWindow` notifies on `height` / `width` / `placement` → `set_default_size` + `dbus.shown()` when docked.
- **✅** JSON: save on window close; immediate save when a toggle key is captured.
- **✅** Default prefs height raised (~20%) so the short page does not need scrolling.

---

## C — Prefs appears under the VTE / drop-down

### Problem

- **🔷** After A2, Preferences opened underneath the always-on-top drop-down.

### Root cause

- **✔️** Drop-down re-dock kept calling `make_above` on itself, so it stayed above Preferences.

### Fix

- **✅** Extension: while Preferences (decorated / title) is open, **`unmake_above` the drop-down** (still visible for live opacity/size); prefs `make_above` + `raise` + activate; on prefs close, `scheduleDock` restores drop-down above.

---

## Attempts / changelog

- **ℹ️** 2026-08-01 — topics merged from earlier prefs / click-stealing logs; VTE split out.
- **✔️** 2026-08-01 — A2 standalone `Adw.Window`.
- **✔️** 2026-08-01 — C2 extension raise / `unmake_above` (v19→v21 cleanup).
- **✔️** 2026-08-01 — B sliders, key capture, live config notify.
- **✅** 2026-08-01 — user: fixed.
