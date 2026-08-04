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
	 * {@link Adw.ComboRow} bound to a Config string property (e.g. placement).
	 *
	 * Replaces the base {@link Row.row} ActionRow with a ComboRow. Options are
	 * the allowed string values in list order.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var placement = new Dialog.RowCombo(config, "placement", { "left", "centre", "right" });
	 * group.add(placement.row);
	 * placement.fill();
	 * }}}
	 */
	public class RowCombo : Row
	{
		public Adw.ComboRow combo;
		private Gtk.StringList model;

		/**
		 * @param config Chrome settings
		 * @param key Hyphenated string property
		 * @param options Allowed values (display strings = stored strings)
		 */
		public RowCombo(Config config, string key, string[] options)
		{
			base(config, key);
			this.model = new Gtk.StringList(null);
			foreach (var option in options) {
				this.model.append(option);
			}
			this.combo = new Adw.ComboRow() {
				title = this.pspec.get_nick(),
				subtitle = this.pspec.get_blurb(),
				model = this.model
			};
			this.row = this.combo;
			this.combo.notify["selected"].connect(() => {
				if (this.combo.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				this.send(this.model.get_string(this.combo.selected));
			});
		}

		public override void fill()
		{
			this.loading = true;
			var value = Value(typeof(string));
			this.read(ref value);
			var text = value.get_string();
			this.combo.selected = Gtk.INVALID_LIST_POSITION;
			for (var i = 0; i < this.model.get_n_items(); i++) {
				if (this.model.get_string(i) != text) {
					continue;
				}
				this.combo.selected = i;
				break;
			}
			this.loading = false;
		}
	}
}
