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
	 * Integer {@link Gtk.Scale} suffix on an {@link Adw.ActionRow} for a Config int.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var height = new Dialog.RowScale(config, "height", 10, 100, 1);
	 * group.add(height.row);
	 * height.fill();
	 * }}}
	 */
	public class RowScale : Row
	{
		public Gtk.Scale scale;

		/**
		 * @param config Chrome settings
		 * @param key Hyphenated int property (``opacity``, ``height``, ``width``)
		 * @param min Scale minimum
		 * @param max Scale maximum
		 * @param step Scale step
		 */
		public RowScale(Config config, string key, double min, double max, double step)
		{
			base(config, key);
			this.scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, min, max, step) {
				draw_value = true,
				digits = 0,
				width_request = 180,
				hexpand = true,
				valign = Gtk.Align.CENTER
			};
			this.scale.value_changed.connect(() => {
				this.send(((int) this.scale.get_value()).to_string());
			});
			((Adw.ActionRow) this.row).add_suffix(this.scale);
		}

		public override void fill()
		{
			this.loading = true;
			var value = Value(typeof(int));
			this.read(ref value);
			this.scale.set_value(value.get_int());
			this.loading = false;
		}
	}
}
