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
	 * hosting an {@link Adw.PreferencesPage} (not a dialog of the drop-down).
	 *
	 * Sliders write {@link RooTerm.Config} live; geometry apply is owned by
	 * {@link RooTerm.MainWindow} via config notify. JSON is saved on Save; Cancel
	 * restores the snapshot from {@link fill}. One instance is kept on
	 * {@link RooTerm.MainWindow.preferences_editor}; Shell owns show/hide.
	 *
	 * == Example ==
	 *
	 * {{{
	 * window.preferences_editor.fill();
	 * window.dbus.call("Show", new GLib.Variant("(s)", "preferences"));
	 * }}}
	 */
	public class Preferences : Adw.Window
	{
		public RooTerm.MainWindow window;
		private Gtk.Button toggle_btn;
		private Gtk.Scale opacity_scale;
		private Gtk.Scale height_scale;
		private Gtk.Scale width_scale;
		private Adw.ComboRow placement_row;
		private bool capturing = false;
		private bool accepting = false;
		private int snap_opacity;
		private int snap_height;
		private int snap_width;
		private string snap_placement;
		private string snap_toggle_key;

		/**
		 * Build the window bound to ``window``'s {@link RooTerm.Config}.
		 *
		 * @param window Main window (config + live apply)
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
			this.map.connect(() => {
				this.window.shell.register(this, "preferences");
			});

			var page = new Adw.PreferencesPage();

			var keyboard = new Adw.PreferencesGroup() {
				title = "Keyboard"
			};
			page.add(keyboard);

			this.toggle_btn = new Gtk.Button.with_label(window.config.toggle_key) {
				valign = Gtk.Align.CENTER
			};
			this.toggle_btn.clicked.connect(() => {
				this.capturing = true;
				this.window.block_toggle = true;
				this.toggle_btn.label = "Press a key…";
			});
			var toggle_row = new Adw.ActionRow() {
				title = "Toggle key",
				subtitle = "Click the button, then press the key"
			};
			toggle_row.add_suffix(this.toggle_btn);
			toggle_row.set_activatable_widget(this.toggle_btn);
			keyboard.add(toggle_row);

			var appearance = new Adw.PreferencesGroup() {
				title = "Appearance"
			};
			page.add(appearance);

			this.opacity_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 10, 100, 1) {
				draw_value = true,
				digits = 0,
				width_request = 180,
				hexpand = true,
				valign = Gtk.Align.CENTER
			};
			this.opacity_scale.set_value(window.config.opacity);
			this.opacity_scale.value_changed.connect(() => {
				this.window.config.opacity = (int) this.opacity_scale.get_value();
			});
			var opacity_row = new Adw.ActionRow() {
				title = "Opacity",
				subtitle = "Terminal background (100 = solid)"
			};
			opacity_row.add_suffix(this.opacity_scale);
			appearance.add(opacity_row);

			this.height_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 10, 100, 1) {
				draw_value = true,
				digits = 0,
				width_request = 180,
				hexpand = true,
				valign = Gtk.Align.CENTER
			};
			this.height_scale.set_value(window.config.height);
			this.height_scale.value_changed.connect(() => {
				this.window.config.height = (int) this.height_scale.get_value();
			});
			var height_row = new Adw.ActionRow() {
				title = "Height",
				subtitle = "Percent of monitor"
			};
			height_row.add_suffix(this.height_scale);
			appearance.add(height_row);

			this.width_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 10, 100, 1) {
				draw_value = true,
				digits = 0,
				width_request = 180,
				hexpand = true,
				valign = Gtk.Align.CENTER
			};
			this.width_scale.set_value(window.config.width);
			this.width_scale.value_changed.connect(() => {
				this.window.config.width = (int) this.width_scale.get_value();
			});
			var width_row = new Adw.ActionRow() {
				title = "Width",
				subtitle = "Percent of monitor"
			};
			width_row.add_suffix(this.width_scale);
			appearance.add(width_row);

			var placement_model = new Gtk.StringList(null);
			placement_model.append("left");
			placement_model.append("centre");
			placement_model.append("right");
			this.placement_row = new Adw.ComboRow() {
				title = "Placement",
				model = placement_model
			};
			switch (window.config.placement) {
				case "left":
					this.placement_row.selected = 0;
					break;

				case "right":
					this.placement_row.selected = 2;
					break;

				default:
					this.placement_row.selected = 1;
					break;
			}
			this.placement_row.notify["selected"].connect(() => {
				switch (this.placement_row.selected) {
					case 0:
						this.window.config.placement = "left";
						break;

					case 2:
						this.window.config.placement = "right";
						break;

					default:
						this.window.config.placement = "centre";
						break;
				}
			});
			appearance.add(this.placement_row);

			var cancel = new Gtk.Button.with_label("Cancel");
			cancel.clicked.connect(() => {
				this.close();
			});
			var save = new Gtk.Button.with_label("Save") {
				css_classes = { "suggested-action" }
			};
			save.clicked.connect(() => {
				this.accepting = true;
				this.save();
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
			header.pack_start(cancel);
			header.pack_end(save);
			var toolbar = new Adw.ToolbarView();
			toolbar.add_top_bar(header);
			toolbar.content = page;
			this.content = toolbar;

			var keys = new Gtk.EventControllerKey() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			keys.key_pressed.connect((keyval, keycode, state) => {
				if (!this.capturing) {
					return false;
				}
				if (keyval == Gdk.Key.Escape) {
					this.capturing = false;
					this.window.block_toggle = false;
					this.toggle_btn.label = this.window.config.toggle_key;
					return true;
				}
				if (keyval == Gdk.Key.Shift_L || keyval == Gdk.Key.Shift_R
						|| keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R
						|| keyval == Gdk.Key.Alt_L || keyval == Gdk.Key.Alt_R
						|| keyval == Gdk.Key.Meta_L || keyval == Gdk.Key.Meta_R
						|| keyval == Gdk.Key.Super_L || keyval == Gdk.Key.Super_R) {
					return true;
				}
				var accel = Gtk.accelerator_name(
					keyval,
					state & Gtk.accelerator_get_default_mod_mask()
				);
				if (accel == null || accel.length == 0) {
					return true;
				}
				this.capturing = false;
				this.window.block_toggle = false;
				this.window.config.toggle_key = accel;
				this.toggle_btn.label = accel;
				var app = this.window.application as RooTerm.Application;
				if (app != null) {
					app.set_accels_for_action("win.toggle", { accel });
				}
				try {
					new RooTerm.GnomeShell(this.window).ensure_toggle_binding(accel);
				} catch (GLib.Error e) {
					GLib.warning("toggle binding: %s", e.message);
				}
				return true;
			});
			// Adw.Window's ShortcutManager.add_controller shadows Widget's.
			((Gtk.Widget) this).add_controller(keys);

			this.close_request.connect(() => {
				if (this.capturing) {
					this.capturing = false;
					this.window.block_toggle = false;
				}
				if (!this.accepting) {
					this.window.config.opacity = this.snap_opacity;
					this.window.config.height = this.snap_height;
					this.window.config.width = this.snap_width;
					this.window.config.placement = this.snap_placement;
					this.window.config.toggle_key = this.snap_toggle_key;
					var app = this.window.application as RooTerm.Application;
					if (app != null) {
						app.set_accels_for_action("win.toggle", {
							this.window.config.toggle_key
						});
					}
					try {
						new RooTerm.GnomeShell(this.window).ensure_toggle_binding(
							this.window.config.toggle_key
						);
					} catch (GLib.Error e) {
						GLib.warning("toggle binding: %s", e.message);
					}
				}
				this.accepting = false;
				this.window.dbus.call("Hide", new GLib.Variant("(s)", "preferences"));
				return true;
			});
			this.fill();
		}

		/**
		 * Reload widgets and Cancel snapshot from {@link RooTerm.MainWindow.config}.
		 */
		public void fill()
		{
			if (this.capturing) {
				this.capturing = false;
				this.window.block_toggle = false;
			}
			this.accepting = false;
			this.snap_opacity = this.window.config.opacity;
			this.snap_height = this.window.config.height;
			this.snap_width = this.window.config.width;
			this.snap_placement = this.window.config.placement;
			this.snap_toggle_key = this.window.config.toggle_key;
			this.toggle_btn.label = this.window.config.toggle_key;
			this.opacity_scale.set_value(this.window.config.opacity);
			this.height_scale.set_value(this.window.config.height);
			this.width_scale.set_value(this.window.config.width);
			switch (this.window.config.placement) {
				case "left":
					this.placement_row.selected = 0;
					break;

				case "right":
					this.placement_row.selected = 2;
					break;

				default:
					this.placement_row.selected = 1;
					break;
			}
		}

		/**
		 * Persist config to disk and refresh the toggle binding.
		 */
		private void save()
		{
			this.window.config.opacity = (int) this.opacity_scale.get_value();
			this.window.config.height = (int) this.height_scale.get_value();
			this.window.config.width = (int) this.width_scale.get_value();
			switch (this.placement_row.selected) {
				case 0:
					this.window.config.placement = "left";
					break;

				case 2:
					this.window.config.placement = "right";
					break;

				default:
					this.window.config.placement = "centre";
					break;
			}
			if (this.toggle_btn.label != "Press a key…" && this.toggle_btn.label.length > 0) {
				this.window.config.toggle_key = this.toggle_btn.label;
			}
			this.window.config.save();
			var app = this.window.application as RooTerm.Application;
			if (app == null) {
				return;
			}
			app.set_accels_for_action("win.toggle", { this.window.config.toggle_key });
			try {
				new RooTerm.GnomeShell(this.window).ensure_toggle_binding(
					this.window.config.toggle_key
				);
			} catch (GLib.Error e) {
				GLib.warning("toggle binding: %s", e.message);
			}
		}
	}
}
