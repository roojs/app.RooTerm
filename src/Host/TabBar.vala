/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace RooTerm.Host
{
	/**
	 * Simple GTK tab strip for an {@link Adw.TabView} (replaces {@link Adw.TabBar}).
	 *
	 * Keeps the view; builds one row button per {@link Adw.TabPage} so width and
	 * chrome are ordinary CSS instead of Adw's expand-tabs-only contract.
	 *
	 * Tab width is ``min(30% of strip, equal share)`` via {@link tab_width}, bound
	 * to each row’s ``width-request``. Titles ellipsize; no scrollbar. Blank space
	 * double-click and ``+`` run ``win.new-terminal``.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var view = new Adw.TabView();
	 * var bar = new Host.TabBar(view);
	 * page_box.append(view);
	 * page_box.append(bar);
	 * }}}
	 */
	public class TabBar : Gtk.Box
	{
		/**
		 * Tab pages this strip mirrors and switches.
		 */
		public Adw.TabView view;

		/**
		 * Shared tab chip width — bound to each row’s ``width-request``.
		 */
		public int tab_width { get; set; default = -1; }

		private Gtk.Box tabs;
		private Gtk.Button add_btn;
		private Gtk.Widget? selected_row;

		/**
		 * Build a bottom strip bound to ``view``, with a ``+`` for ``win.new-terminal``.
		 *
		 * @param view Host page tab view to mirror
		 */
		public TabBar(Adw.TabView view)
		{
			Object(
				orientation: Gtk.Orientation.HORIZONTAL,
				spacing: 0,
				hexpand: true
			);
			this.view = view;
			this.add_css_class("host-tabbar");

			this.tabs = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
			this.tabs.add_css_class("host-tabbar-tabs");
			this.append(this.tabs);
			var blank = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				tooltip_text = "Double-click to open a new terminal"
			};
			var blank_click = new Gtk.GestureClick();
			blank_click.pressed.connect((n_press, x, y) => {
				if (n_press != 2) {
					return;
				}
				this.activate_action("win.new-terminal", null);
			});
			blank.add_controller(blank_click);
			this.append(blank);
			this.add_btn = new Gtk.Button.from_icon_name("list-add-symbolic") {
				tooltip_text = "Ctrl+Shift+T",
				has_frame = false,
				action_name = "win.new-terminal",
				valign = Gtk.Align.CENTER
			};
			this.add_btn.add_css_class("host-tab-add");
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
		}

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

		/**
		 * Build one tab row for ``page`` and insert it at ``position``.
		 *
		 * @param page Tab page to mirror
		 * @param position Index in the strip (same as {@link Adw.TabView.page_attached})
		 */
		private void attach(Adw.TabPage page, int position)
		{
			var label = new Gtk.Label(page.title) {
				ellipsize = Pango.EllipsizeMode.END,
				xalign = 0f,
				hexpand = true
			};
			var pick = new Gtk.Button() {
				child = label,
				has_frame = false,
				hexpand = true,
				tooltip_text = page.tooltip != "" ? page.tooltip : page.title
			};
			pick.add_css_class("host-tab-pick");
			pick.clicked.connect(() => {
				this.view.selected_page = page;
				var term = (Terminal.Base) page.child;
				GLib.Idle.add(() => {
					term.terminal.grab_focus();
					return false;
				});
			});
			var close = new Gtk.Button.from_icon_name("window-close-symbolic") {
				has_frame = false,
				tooltip_text = "Close",
				valign = Gtk.Align.CENTER
			};
			close.add_css_class("host-tab-close");
			close.clicked.connect(() => {
				this.view.close_page(page);
			});
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = false
			};
			row.add_css_class("host-tab");
			var hover = new Gtk.EventControllerMotion();
			hover.enter.connect(() => {
				row.add_css_class("hover");
			});
			hover.leave.connect(() => {
				row.remove_css_class("hover");
			});
			row.add_controller(hover);
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
		}
	}
}
