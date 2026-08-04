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
	 * Accelerator capture button on an {@link Adw.ActionRow} for a Config string
	 * (e.g. ``toggle-key``). Click the button, then press a key; Escape cancels.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var toggle = new Dialog.RowAccel(config, "toggle-key");
	 * group.add(toggle.row);
	 * toggle.fill();
	 * }}}
	 */
	public class RowAccel : Row
	{
		public Gtk.Button button;
		private bool capturing = false;

		/**
		 * @param config Chrome settings
		 * @param key Hyphenated string property (``toggle-key``)
		 */
		public RowAccel(Config config, string key)
		{
			base(config, key);
			this.button = new Gtk.Button.with_label("") {
				valign = Gtk.Align.CENTER
			};
			this.button.clicked.connect(() => {
				this.capturing = true;
				this.button.label = "Press a key…";
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
					this.fill();
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
				return true;
			});
			((Gtk.Widget) this.row).add_controller(keys);
		}

		public override void fill()
		{
			this.loading = true;
			this.capturing = false;
			var value = Value(typeof(string));
			this.read(ref value);
			this.button.label = value.get_string();
			this.loading = false;
		}
	}
}
