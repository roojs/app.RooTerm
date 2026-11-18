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
		 * emit ``items-changed`` so {@link Gtk.TreeListModel} / filters update,
		 * and {@link added} / {@link removed} with the {@link Connection}.
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
		 * Owning config (set by {@link load} on the window tree).
		 */
		public weak RooTerm.Config? config;
		/**
		 * Database for this tree. Set before {@link load} and {@link save}.
		 */
		public SQ.Database db;
		/**
		 * Number of connections that currently have at least one tab.
		 * Root list only.
		 */
		public int num_open { get; set; default = 0; }
		/**
		 * In-flight {@link expand_all} work on this list (the window tree).
		 * Each layer that schedules an idle increments; that idle decrements
		 * after dispatching children. Nested calls pass this same instance
		 * so the count is one queue, not per layer.
		 */
		public int expand_queue { get; set; default = 0; }
		/**
		 * A nested row opened or closed a tab.
		 * {@link Tree} refilters the open-only view.
		 */
		public signal void open_changed();
		/**
		 * ``conn`` was just attached ({@link append} on the root list).
		 * ``conn.parent`` is already set.
		 *
		 * @param conn Row that was attached
		 */
		public signal void added(Connection conn);
		/**
		 * ``conn`` was just detached ({@link remove} on the root list).
		 * ``conn.parent`` is still the old parent.
		 *
		 * @param conn Row that was detached
		 */
		public signal void removed(Connection conn);
		/**
		 * Rows in this layer that can expand (group, localhost, LXC host).
		 * Filled in {@link append} / {@link remove}.
		 */
		public Gee.ArrayList<Connection> expandable {
			get;
			set;
			default = new Gee.ArrayList<Connection>();
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
			switch (conn.kind) {
				case ConnectionKind.GROUP:
				case ConnectionKind.LOCAL:
					add_to.expandable.add(conn);
					break;

				case ConnectionKind.HOST:
					if (conn.lxc_host) {
						add_to.expandable.add(conn);
					}
					break;

				default:
					break;
			}
			this.added(conn);
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
			var add_to = conn.parent == null ? this : conn.parent.children;
			var pos = 0u;
			if (add_to.find(conn, out pos)) {
				add_to.items.remove_at((int) pos);
				add_to.items_changed(pos, 1, 0);
			}
			add_to.expandable.remove(conn);
			conn.tree_row = null;
			this.removed(conn);
			conn.parent = null;
			this.flat.remove(conn);
			if (conn.uuid.length > 0) {
				this.by_uuid.unset(conn.uuid);
			}
		}

		/**
		 * Move ``conn`` under ``parent``, or to the root when ``parent`` is null.
		 * Sessions, the uuid map, and {@link flat} stay put. Writes
		 * ``parent_uuid`` and ``position``.
		 *
		 * @param conn Row to move
		 * @param parent New parent, or ``null`` for a root row
		 * @return Whether the row changed parent
		 */
		public bool reparent(Connection conn, Connection? parent)
		{
			if (conn.parent == parent) {
				return false;
			}
			var walk = parent;
			while (walk != null) {
				if (walk == conn) {
					return false;
				}
				walk = walk.parent;
			}
			var weight = conn.children_open;
			if (conn.sessions.get_n_items() > 0) {
				weight++;
			}
			var from = conn.parent == null ? this : conn.parent.children;
			var pos = 0u;
			if (from.find(conn, out pos)) {
				from.items.remove_at((int) pos);
				from.items_changed(pos, 1, 0);
			}
			from.expandable.remove(conn);
			if (weight != 0) {
				var up = conn.parent;
				while (up != null) {
					up.children_open -= weight;
					up = up.parent;
				}
			}
			conn.tree_row = null;
			conn.parent = parent;
			conn.parent_uuid = parent == null ? "" : parent.uuid;
			var onto = parent == null ? this : parent.children;
			var next = 0;
			for (var i = 0; i < onto.items.size; i++) {
				var sibling = onto.items.get(i).position;
				if (sibling >= next) {
					next = sibling + 1;
				}
			}
			var at = onto.items.size;
			onto.items.add(conn);
			onto.items_changed(at, 0, 1);
			switch (conn.kind) {
				case ConnectionKind.GROUP:
				case ConnectionKind.LOCAL:
					onto.expandable.add(conn);
					break;

				case ConnectionKind.HOST:
					if (conn.lxc_host) {
						onto.expandable.add(conn);
					}
					break;

				default:
					break;
			}
			if (weight != 0) {
				var up = parent;
				while (up != null) {
					up.children_open += weight;
					up = up.parent;
				}
				this.open_changed();
			}
			conn.position = next;
			conn.kind_code = (int) conn.kind;
			conn.updated_dt = (int) new GLib.DateTime.now_local().to_unix();
			if (conn.id < 1) {
				return true;
			}
			new SQ.Query<Connection>(this.db, "connection").updateById(conn);
			return true;
		}

		/**
		 * Groups live only at the root. A group stored under another row
		 * is moved to the root and saved.
		 */
		public void flatten_groups()
		{
			var nested = new Gee.ArrayList<Connection>();
			var pending = new Gee.ArrayList<Connection>();
			for (var i = 0; i < this.size; i++) {
				pending.add(this.get(i));
			}
			var at = 0;
			while (at < pending.size) {
				var conn = pending.get(at);
				at++;
				for (var i = 0; i < conn.children.size; i++) {
					pending.add(conn.children.get(i));
				}
				if (conn.kind != ConnectionKind.GROUP || conn.parent == null) {
					continue;
				}
				nested.add(conn);
			}
			foreach (var conn in nested) {
				var from = conn.parent != null ? conn.parent.name : "";
				if (!this.reparent(conn, null)) {
					continue;
				}
				GLib.debug("group moved to root name=%s from=%s", conn.name, from);
			}
		}

		/**
		 * Expand this layer's rows that have children, then
		 * {@link GLib.Idle.add} {@link expand_all} on those children's lists.
		 * Nested {@link Gtk.TreeListRow}s exist only after the parent expands.
		 * ``counter`` is the window tree whose {@link expand_queue} counts
		 * the work.
		 *
		 * @param counter Queue owner; this list when omitted
		 */
		public void expand_all(TreeNodes? counter = null)
		{
			var owner = counter != null ? counter : this;
			if (this.expandable.size == 0) {
				return;
			}
			owner.expand_queue++;
			foreach (var conn in this.expandable) {
				if (conn.tree_row == null) {
					continue;
				}
				conn.tree_row.expanded = true;
			}
			GLib.Idle.add(() => {
				foreach (var conn in this.expandable) {
					conn.children.expand_all(owner);
				}
				owner.expand_queue--;
				return false;
			});
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
		 * Load the host nest and bind ``config`` and ``db`` on the root list.
		 *
		 * Rows already in ''connection'' win. Otherwise a flat
		 * {@link Config.need_migrate} file or ``connections.json`` is
		 * imported through {@link migrate}, and the JSON file is renamed to
		 * ``connections.json.migrated``.
		 *
		 * @param config From {@link Config.load}
		 * @param db Open database, tables already created
		 * @return Host tree for the window
		 */
		public static TreeNodes load(RooTerm.Config config, SQ.Database db)
		{
			var tree = new TreeNodes();
			tree.config = config;
			tree.db = db;
			var path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "rooterm", "connections.json"
			);
			if (config.need_migrate) {
				try {
					ConfigMigrate.run(tree, config);
				} catch (GLib.Error e) {
					GLib.warning("connections migrate failed: %s", e.message);
				}
				if (GLib.FileUtils.test(path, GLib.FileTest.IS_REGULAR)) {
					if (GLib.FileUtils.rename(path, path + ".migrated") != 0) {
						GLib.warning("connections rename failed");
					}
				}
				tree.flatten_groups();
				return tree;
			}
			var rows = new Gee.ArrayList<Connection>();
			new SQ.Query<Connection>(db, "connection").select("ORDER BY position, id", rows);
			if (rows.size == 0 && !GLib.FileUtils.test(path, GLib.FileTest.IS_REGULAR)) {
				return tree;
			}
			if (rows.size == 0) {
				try {
					string hosts;
					GLib.FileUtils.get_contents(path, out hosts);
					TreeNodes.from_json(Json.from_string(hosts), tree);
					tree.flatten_groups();
					tree.migrate();
				} catch (GLib.Error e) {
					GLib.warning("connections load failed: %s", e.message);
				}
				if (GLib.FileUtils.rename(path, path + ".migrated") != 0) {
					GLib.warning("connections rename failed");
				}
				return tree;
			}
			var left = rows;
			var guard = 0;
			while (left.size > 0 && guard < 8) {
				guard++;
				var still = new Gee.ArrayList<Connection>();
				foreach (var conn in left) {
					conn.kind = (ConnectionKind) conn.kind_code;
					if (conn.uuid.length > 0 && tree.by_uuid.has_key(conn.uuid)) {
						continue;
					}
					if (conn.parent_uuid.length == 0) {
						tree.append(null, conn);
						continue;
					}
					if (!tree.by_uuid.has_key(conn.parent_uuid)) {
						still.add(conn);
						continue;
					}
					tree.append(tree.by_uuid.get(conn.parent_uuid), conn);
				}
				left = still;
			}
			var by_id = new Gee.HashMap<int, Connection>();
			foreach (var conn in tree.by_uuid.values) {
				by_id.set((int) conn.id, conn);
			}
			var forwards = new Gee.ArrayList<Forward>();
			new SQ.Query<Forward>(db, "forward").select("ORDER BY position, id", forwards);
			foreach (var fwd in forwards) {
				if (!by_id.has_key((int) fwd.connection_id)) {
					continue;
				}
				by_id.get((int) fwd.connection_id).forwards.add(fwd);
			}
			GLib.debug("connections loaded count=%d", rows.size);
			tree.flatten_groups();
			if (!GLib.FileUtils.test(path, GLib.FileTest.IS_REGULAR)) {
				return tree;
			}
			if (GLib.FileUtils.rename(path, path + ".migrated") != 0) {
				GLib.warning("connections rename failed");
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
		 * Insert a tree loaded from JSON or Ásbrú. Every row is new.
		 * Used once, from {@link load}, {@link ConfigMigrate.run}, and first-run import.
		 */
		public void migrate()
		{
			var pending = new Gee.ArrayList<Connection>();
			for (var i = 0; i < this.size; i++) {
				var conn = this.get(i);
				conn.position = i;
				pending.add(conn);
			}
			var n = 0;
			while (n < pending.size) {
				var conn = pending.get(n);
				n++;
				for (var i = 0; i < conn.children.size; i++) {
					var child = conn.children.get(i);
					child.position = i;
					pending.add(child);
				}
			}
			var now = (int) new GLib.DateTime.now_local().to_unix();
			var connections = new SQ.Query<Connection>(this.db, "connection");
			var forwards = new SQ.Query<Forward>(this.db, "forward");
			foreach (var conn in pending) {
				conn.kind_code = (int) conn.kind;
				conn.added_dt = now;
				conn.updated_dt = now;
				connections.insert(conn);
				for (var i = 0; i < conn.forwards.size; i++) {
					var fwd = conn.forwards.get(i);
					fwd.connection_id = conn.id;
					fwd.position = i;
					fwd.added_dt = now;
					fwd.updated_dt = now;
					forwards.insert(fwd);
				}
			}
		}
	}
}
