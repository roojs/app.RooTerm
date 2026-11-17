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
	 * Which host-tree rows the planning window shows.
	 *
	 * ''hosts'' is hosts. ''containers'' is LXC.
	 * ''both'' is hosts and containers. Groups stay when a
	 * child stays. Search matches the row or a parent name.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new RooTerm.Filter.Plan();
	 * var rows = new Gtk.FilterListModel(tree, filter);
	 * }}}
	 */
	public class Plan : Gtk.Filter
	{
		public string search { get; set; default = ""; }
		public string scope { get; set; default = "both"; }

		/**
		 * Refilter when {@link search} or {@link scope} changes.
		 */
		public Plan()
		{
			Object();
			this.notify.connect((pspec) => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}

		/**
		 * Whether ''item'' stays in the current scope and search.
		 *
		 * @param item a {@link Host.Connection}
		 * @return true when the row should stay visible
		 */
		public override bool match(GLib.Object? item)
		{
			if (item == null) {
				return false;
			}
			var conn = item as Host.Connection;
			if (conn == null || conn.deleted || conn.id < 1) {
				return false;
			}
			switch (conn.kind) {
				case Host.ConnectionKind.LOCAL:
				case Host.ConnectionKind.LOCAL_PATH:
					return false;

				default:
					break;
			}
			var needle = this.search.strip().down();
			var pending = new Gee.ArrayList<Host.Connection>();
			pending.add(conn);
			var at = 0;
			while (at < pending.size) {
				var node = pending.get(at);
				at++;
				for (var i = 0; i < node.children.size; i++) {
					pending.add(node.children.get(i));
				}
				if (node.deleted || node.id < 1) {
					continue;
				}
				switch (node.kind) {
					case Host.ConnectionKind.HOST:
						if (this.scope == "containers") {
							continue;
						}
						break;

					case Host.ConnectionKind.LXC:
						if (this.scope == "hosts") {
							continue;
						}
						break;

					default:
						continue;
				}
				if (needle == "") {
					return true;
				}
				if (node.name.down().contains(needle)) {
					return true;
				}
				var up = node.parent;
				while (up != null) {
					if (up.name.down().contains(needle)) {
						return true;
					}
					up = up.parent;
				}
			}
			return false;
		}
	}
}
