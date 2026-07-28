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

namespace RooTerm
{
	/**
	 * Flat {@link GLib.ListModel} of openable {@link Connection}s for search.
	 *
	 * Written only by root {@link HostTreeNodes.append} / {@link HostTreeNodes.remove}.
	 */
	public class HostTreeNodesFlat : GLib.Object, GLib.ListModel
	{
		private Gee.ArrayList<Connection> items {
			get;
			set;
			default = new Gee.ArrayList<Connection>();
		}

		/**
		 * Number of openable hosts (Vala ``foreach`` / index access).
		 */
		public int size {
			get { return this.items.size; }
		}

		/**
		 * Host at ``index``.
		 *
		 * @param index Zero-based index
		 * @return The connection at that index
		 */
		public Connection get(int index)
		{
			return this.items.get(index);
		}

		/**
		 * {@inheritDoc}
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Connection);
		}

		/**
		 * {@inheritDoc}
		 */
		public uint get_n_items()
		{
			return this.items.size;
		}

		/**
		 * {@inheritDoc}
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Insert ``connection`` sorted by name and emit ``items-changed``.
		 *
		 * @param connection Openable host to add
		 */
		public void append(Connection connection)
		{
			var at = this.items.size;
			for (var i = 0; i < this.items.size; i++) {
				if (connection.name.collate(this.items.get(i).name) < 0) {
					at = i;
					break;
				}
			}
			this.items.insert(at, connection);
			this.items_changed(at, 0, 1);
		}

		/**
		 * Remove ``connection`` if present and emit ``items-changed``.
		 *
		 * @param connection Host to drop
		 */
		public void remove(Connection connection)
		{
			for (var i = 0; i < this.items.size; i++) {
				if (this.items.get(i) != connection) {
					continue;
				}
				this.items.remove_at(i);
				this.items_changed(i, 1, 0);
				return;
			}
		}

		/**
		 * Find ``connection``; set ``position`` when found.
		 *
		 * @param connection Row to look up
		 * @param position Out index when found
		 * @return Whether the row is in this collection
		 */
		public bool find(Connection connection, out uint position)
		{
			for (var i = 0; i < this.items.size; i++) {
				if (this.items.get(i) != connection) {
					continue;
				}
				position = i;
				return true;
			}
			position = 0;
			return false;
		}
	}
}
