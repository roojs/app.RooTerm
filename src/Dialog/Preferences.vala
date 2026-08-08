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

namespace RooTerm.Dialog
{
	/**
	 * Preferences: standalone {@link Adw.Window} (Shell Show/Hide) with a left
	 * section list and {@link Adw.PreferencesPage}s — **General** (appearance)
	 * and **Keyboard shortcuts** (``key_*``). Rows apply live via {@link Row.send}
	 * / ``config_update``; Close only Hides. Does not write ``config.json``.
	 *
	 * == Example ==
	 *
	 * {{{
	 * window.preferences_editor.fill();
	 * window.dbus.call("show", new GLib.Variant("(s)", "preferences"));
	 * }}}
	 */
	public class Preferences : Adw.Window
	{
		public RooTerm.MainWindow window;
		public Config config;
		public Gee.HashMap<string, Row> rows {
			get;
			set;
			default = new Gee.HashMap<string, Row>();
		}

		/**
		 * Build the window bound to ``window`` (Shell register / hide).
		 *
		 * @param window Main window
		 */
		public Preferences(RooTerm.MainWindow window)
		{
			Object(
				application: window.application,
				title: "Preferences",
				resizable: false,
				hide_on_close: false,
				default_width: 720,
				default_height: 520
			);
			this.add_css_class("floating-dialog");
			this.window = window;
			this.config = Config.load();
			this.config.themes.load();
			this.map.connect(() => {
				// Defer off map — call_sync Register during map deadlocks with Shell.
				GLib.Idle.add(() => {
					this.window.shell.register(this, "preferences");
					return false;
				});
			});

			var general = new Adw.PreferencesPage() {
				title = "General",
				icon_name = "preferences-system-symbolic"
			};
			var appearance = new Adw.PreferencesGroup() { title = "Appearance" };
			general.add(appearance);
			this.add("opacity", new RowScale(this.config, "opacity", 10, 100, 1), appearance);
			this.add("height", new RowScale(this.config, "height", 10, 100, 1), appearance);
			this.add("width", new RowScale(this.config, "width", 10, 100, 1), appearance);
			this.add(
				"placement",
				new RowCombo(this.config, "placement", { "left", "centre", "right" }),
				appearance
			);
			var theme_bg = new RowCombo(
				this.config,
				"theme-category",
				{ "black", "dark-grey", "dark", "off-white", "white" }
			);
			this.add("theme-category", theme_bg, appearance);
			this.add(
				"theme-name",
				new RowThemeSelect(this.config, "theme-name", theme_bg),
				appearance
			);

			var shortcuts = new Adw.PreferencesPage() {
				title = "Keyboard shortcuts",
				icon_name = "input-keyboard-symbolic"
			};
			var keys = new Adw.PreferencesGroup() { title = "Shortcuts" };
			shortcuts.add(keys);
			var toggle = new RowKeySelect(this.config, "key-toggle") {
				block_desktop = true,
				window = this.window
			};
			this.add("key-toggle", toggle, keys);
			this.add("key-search", new RowKeySelect(this.config, "key-search"), keys);
			this.add(
				"key-new-terminal",
				new RowKeySelect(this.config, "key-new-terminal"),
				keys
			);
			this.add("key-new-ssh", new RowKeySelect(this.config, "key-new-ssh"), keys);
			this.add(
				"key-close-terminal",
				new RowKeySelect(this.config, "key-close-terminal"),
				keys
			);
			this.add("key-prev-tab", new RowKeySelect(this.config, "key-prev-tab"), keys);
			this.add("key-next-tab", new RowKeySelect(this.config, "key-next-tab"), keys);
			this.add("key-select-all", new RowKeySelect(this.config, "key-select-all"), keys);
			this.add("key-copy", new RowKeySelect(this.config, "key-copy"), keys);
			this.add("key-paste", new RowKeySelect(this.config, "key-paste"), keys);
			this.add(
				"key-preferences",
				new RowKeySelect(this.config, "key-preferences"),
				keys
			);

			var stack = new Adw.ViewStack();
			stack.add_titled_with_icon(
				general, "general", "General", "preferences-system-symbolic"
			);
			stack.add_titled_with_icon(
				shortcuts, "shortcuts", "Keyboard shortcuts", "input-keyboard-symbolic"
			);

			var nav = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				css_classes = { "navigation-sidebar" }
			};
			nav.append(new Gtk.Label("General") {
				xalign = 0f,
				margin_start = 12,
				margin_end = 12,
				margin_top = 10,
				margin_bottom = 10
			});
			nav.append(new Gtk.Label("Keyboard shortcuts") {
				xalign = 0f,
				margin_start = 12,
				margin_end = 12,
				margin_top = 10,
				margin_bottom = 10
			});
			var side_scroll = new Gtk.ScrolledWindow() {
				child = nav,
				hscrollbar_policy = Gtk.PolicyType.NEVER
			};
			var split = new Adw.NavigationSplitView() {
				sidebar = new Adw.NavigationPage(side_scroll, "Preferences"),
				content = new Adw.NavigationPage(stack, "General"),
				min_sidebar_width = 180,
				max_sidebar_width = 220
			};
			nav.row_selected.connect((row) => {
				if (row == null) {
					return;
				}
				var name = row.get_index() == 0 ? "general" : "shortcuts";
				stack.visible_child_name = name;
				split.content.title = row.get_index() == 0
					? "General" : "Keyboard shortcuts";
			});
			nav.select_row(nav.get_row_at_index(0));

			var close_btn = new Gtk.Button.with_label("Close");
			close_btn.clicked.connect(() => {
				this.close();
			});
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			var no_max = new Gtk.GestureClick() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
				button = Gdk.BUTTON_PRIMARY
			};
			no_max.pressed.connect((n_press, x, y) => {
				if (n_press >= 2) {
					no_max.set_state(Gtk.EventSequenceState.CLAIMED);
				}
			});
			header.add_controller(no_max);
			header.pack_end(close_btn);
			var toolbar = new Adw.ToolbarView();
			toolbar.add_top_bar(header);
			toolbar.content = split;
			this.content = toolbar;

			this.close_request.connect(() => {
				((RowKeySelect) this.rows.get("key-toggle")).fill();
				this.window.dbus.call_async(
					"hide", new GLib.Variant("(s)", "preferences")
				);
				return true;
			});
			this.fill();
		}

		/**
		 * Register a row by config key and add its widget to ``section``.
		 *
		 * @param name Hyphenated Config property name
		 * @param row Row bound to that property
		 * @param section Group that hosts {@link Row.row}
		 */
		public void add(string name, Row row, Adw.PreferencesGroup section)
		{
			this.rows.set(name, row);
			section.add(row.row);
		}

		/**
		 * Reload rows from disk.
		 */
		public void fill()
		{
			this.config = Config.load();
			this.config.themes.load();
			foreach (var row in this.rows.values) {
				row.config = this.config;
				row.fill();
			}
		}
	}
}
