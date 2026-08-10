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
	 * Key-capture button on an {@link Adw.ActionRow} for a Config string
	 * (e.g. ``key-toggle``). Click the button, then press a key; Escape cancels.
	 * Set {@link block_desktop} + {@link shell} for desktop-wide shortcuts
	 * (media-keys).
	 *
	 * == Example ==
	 *
	 * {{{
	 * var toggle = new Dialog.RowKeySelect(config, "key-toggle") {
	 *     block_desktop = true,
	 *     shell = prefs.shell
	 * };
	 * group.add(toggle.row);
	 * toggle.fill();
	 * }}}
	 */
	public class RowKeySelect : Row
	{
		public Gtk.Button button;

		/**
		 * Shell helper for media-keys while capturing a desktop accelerator.
		 * Set with {@link block_desktop} for ``key-toggle``.
		 */
		public GnomeShell shell { get; set; }

		/**
		 * True when this accelerator is owned by the desktop (media-keys), not the
		 * app. Capture then temporarily clears that binding.
		 */
		public bool block_desktop { get; set; default = false; }

		private bool capturing = false;

		/**
		 * @param config Chrome settings
		 * @param key Hyphenated string property (``key-toggle``)
		 */
		public RowKeySelect(Config config, string key)
		{
			base(config, key);
			this.button = new Gtk.Button.with_label("") {
				valign = Gtk.Align.CENTER
			};
			this.button.clicked.connect(() => {
				this.capturing = true;
				this.button.label = "Press a key…";
				if (!this.block_desktop) {
					return;
				}
				try {
					this.shell.ensure_toggle_binding("");
				} catch (GLib.Error e) {
					GLib.warning("toggle binding: %s", e.message);
				}
			});
			((Adw.ActionRow) this.row).add_suffix(this.button);
			((Adw.ActionRow) this.row).set_activatable_widget(this.button);

			var keys = new Gtk.EventControllerKey() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			keys.key_pressed.connect((keyval, keycode, state) => {
				if (!this.capturing) {
					return false;
				}
				if (keyval == Gdk.Key.Escape) {
					this.capturing = false;
					var value = Value(typeof(string));
					this.read(ref value);
					this.button.label = value.get_string();
					if (this.block_desktop) {
						try {
							this.shell.ensure_toggle_binding(value.get_string());
						} catch (GLib.Error e) {
							GLib.warning("toggle binding: %s", e.message);
						}
					}
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
				this.button.label = accel;
				this.send(accel);
				if (this.block_desktop) {
					try {
						this.shell.ensure_toggle_binding(accel);
					} catch (GLib.Error e) {
						GLib.warning("toggle binding: %s", e.message);
					}
				}
				return true;
			});
			((Gtk.Widget) this.row).add_controller(keys);
		}

		public override void fill()
		{
			this.loading = true;
			if (this.capturing && this.block_desktop) {
				var cur = Value(typeof(string));
				this.read(ref cur);
				try {
					this.shell.ensure_toggle_binding(cur.get_string());
				} catch (GLib.Error e) {
					GLib.warning("toggle binding: %s", e.message);
				}
			}
			this.capturing = false;
			var value = Value(typeof(string));
			this.read(ref value);
			this.button.label = value.get_string();
			this.loading = false;
		}
	}
}
