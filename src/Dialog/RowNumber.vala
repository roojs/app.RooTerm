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
	 * Integer {@link Gtk.SpinButton} suffix on an {@link Adw.ActionRow} for a Config int.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var width = new Dialog.RowNumber(config, "width", 1, 100, 1);
	 * group.add(width.row);
	 * width.fill();
	 * }}}
	 */
	public class RowNumber : Row
	{
		public Gtk.SpinButton spin;

		/**
		 * @param config Chrome settings
		 * @param key Hyphenated int property
		 * @param min Spin minimum
		 * @param max Spin maximum
		 * @param step Spin step
		 */
		public RowNumber(Config config, string key, double min, double max, double step)
		{
			base(config, key);
			this.spin = new Gtk.SpinButton.with_range(min, max, step) {
				digits = 0,
				valign = Gtk.Align.CENTER,
				width_request = 100
			};
			this.spin.value_changed.connect(() => {
				this.send(this.spin.get_value_as_int().to_string());
			});
			((Adw.ActionRow) this.row).add_suffix(this.spin);
			((Adw.ActionRow) this.row).set_activatable_widget(this.spin);
		}

		public override void fill()
		{
			this.loading = true;
			var value = Value(typeof(int));
			this.read(ref value);
			this.spin.value = value.get_int();
			this.loading = false;
		}
	}
}
