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
	 * (opacity, height, width, placement). Adwaita ``PreferencesDialog`` with
	 * full-width ``ActionRow`` key–value rows (OLLMchat-style).
	 *
	 * == Example ==
	 *
	 * {{{
	 * var dlg = new Preferences(window);
	 * dlg.present(window);
	 * }}}
	 */
	public class Preferences : Adw.PreferencesDialog
	{
		public MainWindow window;
		private Gtk.Entry toggle_entry;
		private Gtk.SpinButton opacity_spin;
		private Gtk.SpinButton height_spin;
		private Gtk.SpinButton width_spin;
		private Adw.ComboRow placement_row;

		/**
		 * Build the dialog bound to ``window``'s {@link RooTerm.Config}.
		 *
		 * @param window Main window (config + live apply)
		 */
		public Preferences(MainWindow window)
		{
			this.window = window;
			this.title = "Preferences";
			this.set_content_width(520);
			this.set_content_height(420);

			var page = new Adw.PreferencesPage();
			this.add(page);

			var keyboard = new Adw.PreferencesGroup() {
				title = "Keyboard"
			};
			page.add(keyboard);

			this.toggle_entry = new Gtk.Entry() {
				text = window.config.toggle_key,
				width_chars = 12,
				valign = Gtk.Align.CENTER
			};
			var toggle_row = new Adw.ActionRow() {
				title = "Toggle key"
			};
			toggle_row.add_suffix(this.toggle_entry);
			toggle_row.set_activatable_widget(this.toggle_entry);
			keyboard.add(toggle_row);

			var appearance = new Adw.PreferencesGroup() {
				title = "Appearance"
			};
			page.add(appearance);

			this.opacity_spin = new Gtk.SpinButton.with_range(10, 100, 1) {
				value = window.config.opacity,
				valign = Gtk.Align.CENTER,
				width_chars = 6
			};
			var opacity_row = new Adw.ActionRow() {
				title = "Opacity",
				subtitle = "Percent (100 = solid)"
			};
			opacity_row.add_suffix(this.opacity_spin);
			opacity_row.set_activatable_widget(this.opacity_spin);
			appearance.add(opacity_row);

			this.height_spin = new Gtk.SpinButton.with_range(10, 100, 1) {
				value = window.config.height,
				valign = Gtk.Align.CENTER,
				width_chars = 6
			};
			var height_row = new Adw.ActionRow() {
				title = "Height",
				subtitle = "Percent of monitor"
			};
			height_row.add_suffix(this.height_spin);
			height_row.set_activatable_widget(this.height_spin);
			appearance.add(height_row);

			this.width_spin = new Gtk.SpinButton.with_range(10, 100, 1) {
				value = window.config.width,
				valign = Gtk.Align.CENTER,
				width_chars = 6
			};
			var width_row = new Adw.ActionRow() {
				title = "Width",
				subtitle = "Percent of monitor"
			};
			width_row.add_suffix(this.width_spin);
			width_row.set_activatable_widget(this.width_spin);
			appearance.add(width_row);

			var placement_model = new Gtk.StringList(null);
			placement_model.append("left");
			placement_model.append("centre");
			placement_model.append("right");
			this.placement_row = new Adw.ComboRow() {
				title = "Placement",
				model = placement_model
			};
			var place = window.config.placement;
			if (place == "left") {
				this.placement_row.selected = 0;
			} else if (place == "right") {
				this.placement_row.selected = 2;
			} else {
				this.placement_row.selected = 1;
			}
			appearance.add(this.placement_row);

			this.closed.connect(() => {
				this.save();
			});
		}

		/**
		 * Write fields to config, save, apply to the live window.
		 */
		private void save()
		{
			var config = this.window.config;
			var key = this.toggle_entry.text.strip();
			if (key.length == 0) {
				key = "F12";
			}
			config.toggle_key = key;
			config.opacity = (int) this.opacity_spin.value;
			config.height = (int) this.height_spin.value;
			config.width = (int) this.width_spin.value;
			switch (this.placement_row.selected) {
				case 0:
					config.placement = "left";
					break;
				case 2:
					config.placement = "right";
					break;
				default:
					config.placement = "centre";
					break;
			}
			try {
				config.save();
			} catch (GLib.Error e) {
				GLib.warning("config save failed: %s", e.message);
			}
			this.window.opacity = config.opacity / 100.0;
			this.window.set_default_size(
				this.window.monitor_geo.width * config.width / 100,
				this.window.monitor_geo.height * config.height / 100
			);
			var app = this.window.application as Application;
			if (app == null) {
				return;
			}
			app.set_accels_for_action("win.toggle", { config.toggle_key });
			try {
				new GnomeShell(this.window).ensure_toggle_binding(config.toggle_key);
			} catch (GLib.Error e) {
				GLib.warning("toggle binding: %s", e.message);
			}
			app.dbus.shown();
		}
	}
}
