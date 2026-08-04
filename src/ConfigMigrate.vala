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
	 * One-shot: re-read settings JSON that still has flat ``connections``,
	 * build the live tree, write nested ``connections.json`` + clean ``config.json``.
	 * Trash when unused. Called from {@link Host.TreeNodes.load}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * if (config.need_migrate) {
	 *     ConfigMigrate.run(tree, config);
	 * }
	 * }}}
	 */
	public class ConfigMigrate
	{
		/**
		 * Flat list → tree → {@link Host.TreeNodes.save}; chrome → ``config.json``.
		 *
		 * @param tree Window host tree
		 * @param config Flagged instance; {@link Host.TreeNodes.load} calls this when {@link Config.need_migrate}
		 * @throws GLib.Error On read / write failure
		 */
		public static void run(Host.TreeNodes tree, Config config) throws GLib.Error
		{
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "rooterm"
			);
			var connections_path = GLib.Path.build_filename(dir, "connections.json");
			var config_path = GLib.Path.build_filename(dir, "config.json");
			var open_path = GLib.FileUtils.test(config_path, GLib.FileTest.IS_REGULAR)
				? config_path : connections_path;
			string contents;
			GLib.FileUtils.get_contents(open_path, out contents);
			var root = Json.from_string(contents);
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				throw new GLib.IOError.INVALID_DATA("migrate: root is not an object");
			}
			var obj = root.get_object();
			var connections_node = obj.get_member("connections");
			obj.remove_member("connections");

			tree.config = config;
			var flat = new Gee.ArrayList<Host.Connection>();
			if (connections_node != null
					&& connections_node.get_node_type() == Json.NodeType.ARRAY) {
				var json_array = connections_node.get_array();
				for (var i = 0; i < json_array.get_length(); i++) {
					var conn = Json.gobject_deserialize(typeof(Host.Connection), json_array.get_element(i)) as Host.Connection;
					if (conn == null || conn.uuid.length == 0) {
						continue;
					}
					conn.children = new Host.TreeNodes();
					flat.add(conn);
					tree.by_uuid.set(conn.uuid, conn);
				}
			}
			foreach (var conn in flat) {
				if (conn.deleted) {
					continue;
				}
				if (conn.kind == Host.ConnectionKind.LOCAL_PATH) {
					continue;
				}
				Host.Connection? parent = null;
				if (conn.parent_uuid.length > 0 && conn.parent_uuid != "__PAC__ROOT__"
					&& tree.by_uuid.has_key(conn.parent_uuid)) {
					parent = tree.by_uuid.get(conn.parent_uuid);
					if (parent.deleted) {
						parent = null;
					}
				}
				tree.append(parent, conn);
			}
			tree.sort((a, b) => {
				return a.name.collate(b.name);
			});
			foreach (var conn in tree.by_uuid.values) {
				conn.children.sort((a, b) => {
					return a.name.collate(b.name);
				});
			}

			config.need_migrate = false;
			tree.save();
			GLib.FileUtils.set_contents(config_path, Json.to_string(root, true));
			GLib.debug("migrated flat → tree connections=%d roots=%d",
				tree.by_uuid.size, tree.size);
		}
	}
}
