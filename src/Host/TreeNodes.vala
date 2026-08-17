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

namespace RooTerm.Host
{
	/**
	 * Nested collection of {@link Connection} rows for the host tree.
	 *
	 * Implements {@link GLib.ListModel} over a {@link Gee.ArrayList}; mutations
	 * emit ``items-changed`` so {@link Gtk.TreeListModel} / filters update.
	 *
	 * The root list (``MainWindow.tree``) also owns {@link flat}; use
	 * {@link append} / {@link remove} for nest + flat updates.
	 */
	public class TreeNodes : GLib.Object, GLib.ListModel
	{
		private Gee.ArrayList<Connection> items {
			get;
			set;
			default = new Gee.ArrayList<Connection>();
		}
		/**
		 * Openable hosts for search (used on the root list only).
		 */
		public TreeNodesFlat flat {
			get;
			set;
			default = new TreeNodesFlat();
		}
		/**
		 * uuid → connection (root list only).
		 */
		public Gee.HashMap<string, Connection> by_uuid {
			get;
			set;
			default = new Gee.HashMap<string, Connection>();
		}
		/**
		 * Owning config (set by {@link load} on the window tree); used to save on expand.
		 */
		public weak RooTerm.Config? config;
		/**
		 * Number of connections that currently have at least one tab.
		 * Root list only.
		 */
		public int num_open { get; set; default = 0; }
		/**
		 * A nested row opened or closed a tab.
		 * {@link Tree} refilters the open-only view.
		 */
		public signal void open_changed();

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
			GLib.error("use tree.append(parent, conn)");
		}

		/**
		 * Not supported — use root {@link append}.
		 *
		 * @param position Ignored
		 * @param connection Ignored
		 */
		public void insert(uint position, Connection connection)
		{
			GLib.error("use tree.append(parent, conn)");
		}

		/**
		 * Not supported — use root {@link remove}.
		 *
		 * @param position Ignored
		 */
		public void remove_at(uint position)
		{
			GLib.error("use tree.remove(conn)");
		}

		/**
		 * Not supported — use root {@link remove}.
		 */
		public void remove_all()
		{
			GLib.error("use tree.remove(conn)");
		}

		/**
		 * Place ``conn`` under ``parent`` (or this list) and update {@link flat}.
		 * Call on the root list (``MainWindow.tree``).
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
			if (conn.uuid.length > 0) {
				this.by_uuid.set(conn.uuid, conn);
			}
			conn.sessions.items_changed.connect((pos, removed, added) => {
				var n = conn.sessions.get_n_items();
				var prev = n - added + removed;
				var adjust = prev == 0 && n > 0 ? 1 : prev > 0 && n == 0 ? -1 : 0;
				if (adjust == 0) {
					return;
				}
				this.num_open += adjust;
				var up = conn.parent;
				while (up != null) {
					up.children_open += adjust;
					up = up.parent;
				}
				this.open_changed();
			});
			if (conn.sessions.get_n_items() > 0) {
				this.num_open++;
				var up = conn.parent;
				while (up != null) {
					up.children_open++;
					up = up.parent;
				}
			}
			if ((conn.kind == ConnectionKind.GROUP || conn.lxc_host)
				&& conn.expand_save_sid == 0) {
				conn.expand_save_sid = conn.notify["expanded"].connect(() => {
					this.save();
				});
			}
			if (conn.deleted || conn.kind == ConnectionKind.GROUP) {
				this.open_changed();
				return;
			}
			this.flat.append(conn);
			this.open_changed();
		}

		/**
		 * Detach ``conn`` from its parent list (or this list) and from {@link flat}.
		 * Call on the root list (``MainWindow.tree``).
		 *
		 * @param conn Row to detach ({@link Connection.parent} must be current)
		 */
		public void remove(Connection conn)
		{
			if (conn.expand_save_sid != 0) {
				conn.disconnect(conn.expand_save_sid);
				conn.expand_save_sid = 0;
			}
			var add_to = conn.parent == null ? this : conn.parent.children;
			var pos = 0u;
			if (add_to.find(conn, out pos)) {
				add_to.items.remove_at((int) pos);
				add_to.items_changed(pos, 1, 0);
			}
			conn.parent = null;
			this.flat.remove(conn);
			if (conn.uuid.length > 0) {
				this.by_uuid.unset(conn.uuid);
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

		/**
		 * Load the host nest and bind ``config`` for expand→save.
		 * Migrate if {@link Config.need_migrate}, else ``connections.json`` when present.
		 * Read failures log a warning only.
		 *
		 * @param config From {@link Config.load}
		 * @return Host tree for the window
		 */
		public static TreeNodes load(RooTerm.Config config)
		{
			var tree = new TreeNodes();
			tree.config = config;
			if (config.need_migrate) {
				try {
					ConfigMigrate.run(tree, config);
				} catch (GLib.Error e) {
					GLib.warning("connections migrate failed: %s", e.message);
				}
				return tree;
			}
			var path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "rooterm", "connections.json"
			);
			if (!GLib.FileUtils.test(path, GLib.FileTest.IS_REGULAR)) {
				return tree;
			}
			try {
				string hosts;
				GLib.FileUtils.get_contents(path, out hosts);
				TreeNodes.from_json(Json.from_string(hosts), tree);
			} catch (GLib.Error e) {
				GLib.warning("connections load failed: %s", e.message);
			}
			return tree;
		}

		/**
		 * Load a JSON array of {@link Connection} into ``root`` via {@link append}.
		 * Nested ``children`` are read for the recurse; deserialize leaves ``children`` empty
		 * ({@link Connection} does not build the nest).
		 *
		 * @param node JSON array (empty / non-array → no-op)
		 * @param root Live tree (``MainWindow.tree``); must have ``config`` set before call
		 * @param parent Parent for these rows, or ``null`` for roots
		 */
		public static void from_json(Json.Node? node, TreeNodes root, Connection? parent = null)
		{
			if (node == null || node.get_node_type() != Json.NodeType.ARRAY) {
				return;
			}
			var json_array = node.get_array();
			for (var i = 0; i < json_array.get_length(); i++) {
				var element = json_array.get_element(i);
				if (element.get_node_type() != Json.NodeType.OBJECT) {
					continue;
				}
				var obj = element.get_object();
				Json.Node? children_node = obj.has_member("children")
					? obj.get_member("children") : null;
				var conn = Json.gobject_deserialize(typeof(Connection), element) as Connection;
				if (conn == null) {
					continue;
				}
				if (conn.uuid.length > 0 && root.by_uuid.has_key(conn.uuid)) {
					GLib.debug("skip duplicate uuid=%s name=%s", conn.uuid, conn.name);
					continue;
				}
				root.append(parent, conn);
				TreeNodes.from_json(children_node, root, conn);
			}
		}

		/**
		 * Write ``~/.config/rooterm/connections.json`` as nested roots (no passwords).
		 */
		public void save()
		{
			var path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "rooterm", "connections.json"
			);
			var arr = new Json.Array();
			foreach (var conn in this) {
				arr.add_element(Json.gobject_serialize(conn));
			}
			var node = new Json.Node(Json.NodeType.ARRAY);
			node.take_array(arr);
			try {
				GLib.FileUtils.set_contents(path, Json.to_string(node, true));
			} catch (GLib.Error e) {
				GLib.warning("connections save failed: %s", e.message);
			}
		}
	}
}
