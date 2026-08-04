# Bottom tabs: weak visual affordance / hover skips close

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ⏳ proposed CSS — await apply approval

**Started:** 2026-08-04

**Related:**

- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-tab-password-localhost-tree.md` — dropped `Adw.TabBar` for `Host.TabBar` (width / expand)
- **ℹ️** `src/Host/TabBar.vala` — row = `.host-tab` box + `.host-tab-pick` + `.host-tab-close`
- **ℹ️** `resources/style.css` — `.host-tab` / `.selected` only; no row hover

---

## Problem

- **🔷** Bottom host tabs do not read as tabs at rest — easy to miss that they are clickable chrome.
- **🔷** Hover highlight covers only the title button, not the close (×) — feels broken / inconsistent.
- **🔷** Expect a **minimal** resting indication that these are tabs, plus hover that covers the whole chip.

### Reproduction

1. Open a host with one or more terminal tabs (bottom strip).
2. Look at the strip without hovering.
3. **Actual:** soft fill only; little “tab” cue; selected accent is easy to miss.
4. Hover the title → highlight stops before ×; hover × → only × lights up.

---

## Evidence

- **✔️** Each tab is a `Gtk.Box.host-tab` with two frameless `Gtk.Button`s (`host-tab-pick`, `host-tab-close`) — see `Host.TabBar.attach()`.
- **✔️** Theme hover is on `button:hover`, so pick and close hover independently; the row has no `:hover` CSS.
- **✔️** Current resting / selected styles:

```css
.host-tab {
	min-height: 24px;
	padding: 0 2px 0 4px;
	border-radius: 4px;
	background-color: alpha(@view_bg_color, 0.6);
}

.host-tab.selected {
	background-color: alpha(@accent_bg_color, 0.35);
}
```

- **🚫** Revert to `Adw.TabBar` — already rejected (expand / width contract). Keep `Host.TabBar`.

---

## Root cause

- **✔️** Affordance is CSS-only and under-specified: no border / separator / underline; hover owned by child buttons instead of the chip.

---

## Proposed fix

- **🔷** CSS-only on `Host.TabBar` chrome — no Vala / no `Adw.TabBar`.
- **🔷** Whole-chip hover (including ×); mute per-button hover so it does not fight the row.
- **🔷** Minimal resting chrome: light border + slightly clearer selected (fill + bottom accent bar).

### `resources/style.css` — `.host-tab` block: resting, selected, hover

**Why:** Make chips readable at rest; one hover surface for title + close.

**Where:** Replace the existing `.host-tab` / `.host-tab.selected` / `.host-tab-pick` / `.host-tab-close` rules (after the `.host-tabbar` block).

**Depends on:** none.

#### Remove

```css
.host-tab {
	min-height: 24px;
	padding: 0 2px 0 4px;
	border-radius: 4px;
	background-color: alpha(@view_bg_color, 0.6);
}

.host-tab.selected {
	background-color: alpha(@accent_bg_color, 0.35);
}

.host-tab-pick,
.host-tab-close {
	min-height: 22px;
	padding: 0 4px;
}

.host-tab-close {
	min-width: 22px;
	padding: 0;
}
```

#### Replace with

```css
.host-tab {
	min-height: 24px;
	padding: 0 2px 0 4px;
	border-radius: 4px;
	border: 1px solid alpha(@borders, 0.55);
	background-color: alpha(@view_bg_color, 0.75);
}

.host-tab:hover {
	background-color: alpha(@view_bg_color, 0.95);
}

.host-tab.selected {
	background-color: alpha(@accent_bg_color, 0.35);
	box-shadow: inset 0 -2px 0 @accent_bg_color;
}

.host-tab.selected:hover {
	background-color: alpha(@accent_bg_color, 0.45);
}

/* Hover chrome lives on the row; do not paint pick/close separately. */
.host-tab-pick,
.host-tab-close {
	min-height: 22px;
	padding: 0 4px;
}

.host-tab-pick:hover,
.host-tab-close:hover,
.host-tab-pick:active,
.host-tab-close:active {
	background: transparent;
	box-shadow: none;
}

.host-tab-close {
	min-width: 22px;
	padding: 0;
}
```

---

## Attempts / changelog

- **ℹ️** 2026-08-04 — investigated; hover gap is structural (two buttons); Adw CSS not useful on-disk (Adw 1.7 baked-in).
- **💩** 2026-08-04 — proposed CSS above (border + underline-selected + row hover).

## Next

- **⏳** **🔷** Approve → apply `resources/style.css` hunk; restart app to reload gresource CSS.
- **⏳** **🔷** Device: tabs readable at rest; hover covers title + ×; selected underline clear; no Adw.TabBar.
