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
	 * Nested collection of {@link Connection} rows for the host tree.
	 *
	 * Implements {@link GLib.ListModel} over a {@link Gee.ArrayList}; mutations
	 * emit ``items-changed`` so {@link Gtk.TreeListModel} / filters update.
	 *
	 * The root list (``Config.tree``) also owns {@link flat}; use
	 * {@link append} / {@link remove} for nest + flat updates.
	 */
	public class HostTreeNodes : GLib.Object, GLib.ListModel
	{
		private Gee.ArrayList<Connection> items {
			get;
			set;
			default = new Gee.ArrayList<Connection>();
		}
		/**
		 * Openable hosts for search (used on the root list only).
		 */
		public HostTreeNodesFlat flat {
			get;
			set;
			default = new HostTreeNodesFlat();
		}

		/**
		 * Number of rows (Vala ``foreach`` / index access).
		 */
		public int size {
			get { return this.items.size; }
		}

		/**
		 * Row at ``index`` (Vala ``foreach`` / index access).
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
		 * Not supported — use root {@link append}.
		 *
		 * @param connection Ignored
		 */
		public void add(Connection connection)
		{
			GLib.error("use Config.tree.append(parent, conn)");
		}

		/**
		 * Not supported — use root {@link append}.
		 *
		 * @param position Ignored
		 * @param connection Ignored
		 */
		public void insert(uint position, Connection connection)
		{
			GLib.error("use Config.tree.append(parent, conn)");
		}

		/**
		 * Not supported — use root {@link remove}.
		 *
		 * @param position Ignored
		 */
		public void remove_at(uint position)
		{
			GLib.error("use Config.tree.remove(conn)");
		}

		/**
		 * Not supported — use root {@link remove}.
		 */
		public void remove_all()
		{
			GLib.error("use Config.tree.remove(conn)");
		}

		/**
		 * Place ``conn`` under ``parent`` (or this list) and update {@link flat}.
		 * Call on the root list (``Config.tree``).
		 *
		 * @param parent Parent connection, or ``null`` for a root row
		 * @param conn Row to attach
		 */
		public void append(Connection? parent, Connection conn)
		{
			var add_to = parent == null ? this : parent.children;
			var position = add_to.items.size;
			add_to.items.add(conn);
			add_to.items_changed(position, 0, 1);
			conn.parent = parent;
			conn.parent_uuid = parent == null ? "" : parent.uuid;
			if (conn.deleted || conn.is_group) {
				return;
			}
			this.flat.append(conn);
		}

		/**
		 * Detach ``conn`` from its parent list (or this list) and from {@link flat}.
		 * Call on the root list (``Config.tree``).
		 *
		 * @param conn Row to detach ({@link Connection.parent} must be current)
		 */
		public void remove(Connection conn)
		{
			var add_to = conn.parent == null ? this : conn.parent.children;
			var pos = 0u;
			if (add_to.find(conn, out pos)) {
				add_to.items.remove_at((int) pos);
				add_to.items_changed(pos, 1, 0);
			}
			conn.parent = null;
			this.flat.remove(conn);
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

		/**
		 * Sort rows and emit ``items-changed`` for the whole list.
		 *
		 * @param compare Compare callback for two {@link Connection}s
		 */
		public void sort(owned GLib.CompareDataFunc<Connection> compare)
		{
			var n = this.items.size;
			if (n < 2) {
				return;
			}
			this.items.sort((owned) compare);
			this.items_changed(0, n, n);
		}
	}
}
