# Tab bar scrolls instead of shrink-to-fit

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed out 2026-08-04

**Started:** 2026-08-04

**Related:**

- **ℹ️** `docs/plans/done/0.3-DONE-session-states-history-guake.md` — many tabs: **cramp / shrink**, ellipsis; **🚫** Guake tab scroll buttons
- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-tab-password-localhost-tree.md` — `Host.TabBar`; agreed width: **min(30% of strip, equal share)**
- **ℹ️** `src/Host/TabBar.vala` — current: fixed `width_request = 280` + horizontal `ScrolledWindow`
- **ℹ️** GTK CSS has **no** `max-width` (theme parser error) — cap must be Vala `width_request`

---

## Problem

- **🔷** With more than ~3–4 tabs, the bottom strip grows a **horizontal scrollbar** instead of resizing tabs to fit.
- **🔷** Agreed design: each tab width = **`min(30% of strip, equal share)`** — few tabs stay medium-wide; many shrink; titles ellipsize; **no scrollbar**.

### Reproduction

1. Open a host page and create 4+ terminal tabs.
2. **Actual:** scrollbar on the tab strip; tabs stay ~280px.
3. **Expected:** tabs shrink equally to fit the strip (at most ~30% each when few).

---

## Evidence

- **✔️** `Host.TabBar` wraps tabs in `Gtk.ScrolledWindow` with `hscrollbar_policy = AUTOMATIC`.
- **✔️** Each row uses fixed `width_request = 280`, `hexpand = false`.
- **✔️** Prior chat / bug A: CSS `max-width` is invalid in GTK → warning `No property named "max-width"`.
- **✔️** User (2026-08-04): scrollbar with lots of tabs is the regression; design is shrink-to-fit, not scroll.

---

## Root cause

- **✔️** Fixed pixel width + scrolled strip **overrides** the agreed shrink-to-fit contract. Overflow becomes a scrollbar instead of recalculating `width_request`.

---

## Agreed design (do not reinvent)

- **🔷** Width per tab: `min((avail * 0.30), (avail - gaps) / n)` where `avail` is strip width minus the `+` button.
- **🔷** No horizontal scrollbar / no scroll buttons.
- **🔷** Ellipsize titles; tooltip keeps the full path.
- **🚫** CSS `max-width` (does not exist in GTK).
- **🚫** Pure `hexpand` with no 30% cap (one tab fills the strip).
- **🚫** New helper methods / rebuild-the-strip rewrites unless explicitly asked (`docs/guide-to-writing-plans.md` — no helpers without asking).

---

## Proposed fix

- **🔷** Bind each tab row’s `width-request` to a `TabBar.tab_width` property at create time — change one property, all tabs update.
- **🔷** On the `Adw.TabPage`: `set_data("tab-row", row)` and `set_data("width-binding", …)` at attach — look up from `page` (signal already has it); **🚫** HashMap, **🚫** sibling walks.
- **🔷** Unbind on detach — `unbind()` before `remove`.
- **🔷** Selected chrome: keep `selected_row`; on `notify["selected-page"]` clear the old row, set the new — **🚫** iterate all tabs.
- **💩** Minimal change on existing `Host.TabBar` (`attach` stays):
  1. Drop the `ScrolledWindow`; append `tabs` directly.
  2. `add_btn` field for measure; `tab_width` property; `selected_row` field.
  3. `attach`: create row, bind, `page.set_data(…)` for row + binding; insert via `get_nth_page(…).get_data("tab-row")`; if selected, set `selected_row`.
  4. Detach: unbind → remove; if that row was `selected_row`, clear it.
  5. `size_allocate`: compute `min(30%, equal share)` → `this.tab_width` only.
- **⏳** **🔷** Await approval before any code edit. → **✔️** approved and applied 2026-08-04.

### `src/Host/TabBar.vala` — drop scroll; set_data on page; bind width

**Why:** Agreed shrink-to-fit; no scrollbar; page already carries the row pointer; one property drives all chip widths.

**Where:** fields, ctor handlers, `attach`, `size_allocate`.

**Depends on:** none.

#### Add (fields / property)

```vala
		/**
		 * Shared tab chip width — bound to each row’s ``width-request``.
		 */
		public int tab_width { get; set; default = -1; }

		private Gtk.Button add_btn;
		private Gtk.Widget? selected_row;
```

#### Remove

```vala
			var scroll = new Gtk.ScrolledWindow() {
				hexpand = true,
				vscrollbar_policy = Gtk.PolicyType.NEVER,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				propagate_natural_height = true,
				has_frame = false
			};
			this.tabs = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
			this.tabs.add_css_class("host-tabbar-tabs");
			scroll.set_child(this.tabs);
			this.append(scroll);
			this.append(new Gtk.Button.from_icon_name("list-add-symbolic") {
				tooltip_text = "Ctrl+Shift+T",
				has_frame = false,
				action_name = "win.new-terminal",
				valign = Gtk.Align.CENTER
			});

			this.view.page_attached.connect((page, position) => {
				this.attach(page, position);
			});
			this.view.page_detached.connect((page, position) => {
				var child = this.tabs.get_first_child();
				for (var i = 0; i < position; i++) {
					child = child.get_next_sibling();
				}
				this.tabs.remove(child);
			});
			this.view.page_reordered.connect((page, position) => {
				Gtk.Widget moving = null;
				var child = this.tabs.get_first_child();
				while (child != null) {
					if (child.get_data<Adw.TabPage>("page") == page) {
						moving = child;
						break;
					}
					child = child.get_next_sibling();
				}
				this.tabs.remove(moving);
				if (position == 0) {
					this.tabs.prepend(moving);
					return;
				}
				var after = this.tabs.get_first_child();
				for (var i = 1; i < position; i++) {
					after = after.get_next_sibling();
				}
				this.tabs.insert_child_after(moving, after);
			});
			this.view.notify["selected-page"].connect(() => {
				var child = this.tabs.get_first_child();
				while (child != null) {
					if (child.get_data<Adw.TabPage>("page") == this.view.selected_page) {
						child.add_css_class("selected");
					} else {
						child.remove_css_class("selected");
					}
					child = child.get_next_sibling();
				}
			});
```

#### Replace with

```vala
			this.tabs = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2) {
				hexpand = true
			};
			this.tabs.add_css_class("host-tabbar-tabs");
			this.append(this.tabs);
			this.add_btn = new Gtk.Button.from_icon_name("list-add-symbolic") {
				tooltip_text = "Ctrl+Shift+T",
				has_frame = false,
				action_name = "win.new-terminal",
				valign = Gtk.Align.CENTER
			};
			this.append(this.add_btn);

			this.view.page_attached.connect((page, position) => {
				this.attach(page, position);
			});
			this.view.page_detached.connect((page, position) => {
				var row = page.get_data<Gtk.Widget>("tab-row");
				page.get_data<GLib.Binding>("width-binding").unbind();
				this.tabs.remove(row);
				if (row == this.selected_row) {
					this.selected_row = null;
				}
			});
			this.view.page_reordered.connect((page, position) => {
				var moving = page.get_data<Gtk.Widget>("tab-row");
				this.tabs.remove(moving);
				if (position == 0) {
					this.tabs.prepend(moving);
					return;
				}
				this.tabs.insert_child_after(moving,
					this.view.get_nth_page(position - 1).get_data<Gtk.Widget>("tab-row"));
			});
			this.view.notify["selected-page"].connect(() => {
				if (this.selected_row != null) {
					this.selected_row.remove_css_class("selected");
					this.selected_row = null;
				}
				if (this.view.selected_page == null) {
					return;
				}
				this.selected_row = this.view.selected_page.get_data<Gtk.Widget>("tab-row");
				this.selected_row.add_css_class("selected");
			});
```

#### Remove (in `attach`)

```vala
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = false,
				width_request = 280
			};
			row.add_css_class("host-tab");
			row.set_data("page", page);
			if (page == this.view.selected_page) {
				row.add_css_class("selected");
			}
			row.append(pick);
			row.append(close);
			page.notify["title"].connect(() => {
				label.label = page.title;
				pick.tooltip_text = page.tooltip != "" ? page.tooltip : page.title;
			});
			page.notify["tooltip"].connect(() => {
				pick.tooltip_text = page.tooltip != "" ? page.tooltip : page.title;
			});
			if (position == 0) {
				this.tabs.prepend(row);
				return;
			}
			var after = this.tabs.get_first_child();
			for (var i = 1; i < position; i++) {
				after = after.get_next_sibling();
			}
			this.tabs.insert_child_after(row, after);
```

#### Replace with

```vala
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = false
			};
			row.add_css_class("host-tab");
			page.set_data("tab-row", row);
			page.set_data("width-binding", this.bind_property(
				"tab-width", row, "width-request", GLib.BindingFlags.SYNC_CREATE
			));
			if (page == this.view.selected_page) {
				row.add_css_class("selected");
				this.selected_row = row;
			}
			row.append(pick);
			row.append(close);
			page.notify["title"].connect(() => {
				label.label = page.title;
				pick.tooltip_text = page.tooltip != "" ? page.tooltip : page.title;
			});
			page.notify["tooltip"].connect(() => {
				pick.tooltip_text = page.tooltip != "" ? page.tooltip : page.title;
			});
			if (position == 0) {
				this.tabs.prepend(row);
				return;
			}
			this.tabs.insert_child_after(row,
				this.view.get_nth_page(position - 1).get_data<Gtk.Widget>("tab-row"));
```

#### Add (after ctor closes — before `attach`)

```vala
		public override void size_allocate(int width, int height, int baseline)
		{
			if (this.view.n_pages <= 0 || width <= 0) {
				base.size_allocate(width, height, baseline);
				return;
			}
			var add_min = 0, add_nat = 0;
			this.add_btn.measure(Gtk.Orientation.HORIZONTAL, -1,
				out add_min, out add_nat, null, null);
			if (width <= add_nat) {
				base.size_allocate(width, height, baseline);
				return;
			}
			var w = int.min((int) ((width - add_nat) * 0.30),
				(width - add_nat - 2 * (this.view.n_pages - 1)) / this.view.n_pages);
			if (w == this.tab_width) {
				base.size_allocate(width, height, baseline);
				return;
			}
			this.tab_width = w;
			base.size_allocate(width, height, baseline);
		}
```

Update class doc to describe `min(30%, equal share)` via bound `tab_width` (no scroll).

### `resources/style.css` — comment only

**Why:** Document that width is Vala, not CSS.

#### Remove

```css
/* Bottom host tab strip (Host.TabBar — not Adw.TabBar).
 * Tab width is width_request on the row (no hexpand); strip scrolls when crowded. */
```

#### Replace with

```css
/* Bottom host tab strip (Host.TabBar — not Adw.TabBar).
 * Width: Vala tab_width property (bound to each .host-tab width-request).
 * Do not use CSS max-width — GTK has no such property. */
```

---

## Attempts / changelog

- **💩** 2026-08-04 — agent tried CSS `max-width: 30%` + `hexpand` (invalid / wrong).
- **💩** 2026-08-04 — agent tried pure `hexpand` with no 30% cap (one tab fills bar).
- **💩** 2026-08-04 — agent rewrote strip with helpers / rebuild / constants — **rejected**; **reverted** `TabBar.vala` + `style.css` to pre-botch (`0660b32`, before `ca738fc`).
- **ℹ️** 2026-08-04 — this bug file opened; no fix applied until approved.
- **💩** 2026-08-04 — `size_allocate` proposal amended: early returns, no `n`/`avail` aliases, one `int.min` for 30% vs equal-share, `var add_min = 0, add_nat = 0`.
- **🔷** 2026-08-04 — bind each row `width-request` to `TabBar.tab_width`; `size_allocate` only sets the property (no child walk).
- **🔷** 2026-08-04 — unbind on detach.
- **💩** 2026-08-04 — briefly proposed `by_page` HashMap — dropped.
- **🔷** 2026-08-04 — `page.set_data("tab-row" / "width-binding")`; detach / reorder use that (no map, no sibling hunt).
- **🔷** 2026-08-04 — selected: track `selected_row`, update old + new only (no iterate-all).
- **✔️** 2026-08-04 — approved fix applied to `TabBar.vala` + CSS comment.
- **✅** 2026-08-04 — user: close out tab shrink bug.

## Next

- **✅** 2026-08-04 — closed out; moved to `docs/bugs/done/`.
