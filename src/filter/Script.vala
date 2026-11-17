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

namespace RooTerm.Filter
{
	/**
	 * Search for the script sender list.
	 *
	 * Matches the nickname and the command text. An empty
	 * search shows every script.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new RooTerm.Filter.Script();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class Script : Gtk.Filter
	{
		public string search { get; set; default = ""; }

		/**
		 * Refilter when {@link search} changes.
		 */
		public Script()
		{
			Object();
			this.notify.connect((pspec) => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}

		/**
		 * Whether ''item'' matches {@link search}.
		 *
		 * @param item a {@link RooTerm.SQT.Script}
		 * @return true when the row should stay visible
		 */
		public override bool match(GLib.Object? item)
		{
			if (item == null) {
				return false;
			}
			var row = (RooTerm.SQT.Script) item;
			var needle = this.search.strip().down();
			if (needle == "") {
				return true;
			}
			if (row.path.down().contains(needle)) {
				return true;
			}
			return row.body.down().contains(needle);
		}
	}
}
