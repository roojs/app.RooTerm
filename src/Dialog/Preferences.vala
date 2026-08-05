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
	 * Single-page preferences: Keyboard (toggle key) and Appearance
	 * (opacity, height, width, placement). Standalone {@link Adw.Window}
	 * hosting an {@link Adw.PreferencesPage}. Rows apply live via
	 * {@link Row.send} / ``config_update``; Close only Hides (no undo).
	 * This window does not write ``config.json``.
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
				default_width: 520,
				default_height: 504
			);
			this.add_css_class("floating-dialog");
			this.window = window;
			this.config = Config.load();
			this.map.connect(() => {
				this.window.shell.register(this, "preferences");
			});

			var page = new Adw.PreferencesPage();
			var keyboard = new Adw.PreferencesGroup() { title = "Keyboard" };
			page.add(keyboard);
			this.add("toggle-key", new RowAccel(this.config, "toggle-key"), keyboard);

			var appearance = new Adw.PreferencesGroup() { title = "Appearance" };
			page.add(appearance);
			this.add("opacity", new RowScale(this.config, "opacity", 10, 100, 1), appearance);
			this.add("height", new RowScale(this.config, "height", 10, 100, 1), appearance);
			this.add("width", new RowScale(this.config, "width", 10, 100, 1), appearance);
			this.add(
				"placement",
				new RowCombo(this.config, "placement", { "left", "centre", "right" }),
				appearance
			);

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
			toolbar.content = page;
			this.content = toolbar;

			this.close_request.connect(() => {
				this.window.dbus.call("hide", new GLib.Variant("(s)", "preferences"));
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
			foreach (var row in this.rows.values) {
				row.config = this.config;
				row.fill();
			}
		}
	}
}
