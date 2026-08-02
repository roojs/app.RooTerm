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
	 * RooTerm ``connections.json``: load/save and one-shot Ásbrú import.
	 */
	public class Config : Object, Json.Serializable
	{
		public int version { get; set; default = 1; }
		public string terminal_font { get; set; default = "Monospace 9"; }
		/**
		 * Drop-down width as percent of the monitor (1–100). Full width for now.
		 */
		public int width { get; set; default = 100; }
		/**
		 * Drop-down height as percent of the monitor (1–100).
		 */
		public int height { get; set; default = 60; }
		/**
		 * Guake global toggle key (Shell extension / ``--toggle-key``).
		 */
		public string toggle_key { get; set; default = "F12"; }
		/**
		 * VTE background opacity percent (10–100). Host chrome stays opaque.
		 */
		public int opacity { get; set; default = 100; }
		/**
		 * Horizontal placement on the monitor: ``left``, ``centre``, or ``right``.
		 */
		public string placement { get; set; default = "centre"; }
		public Gee.ArrayList<Host.Connection> connections {
			get;
			set;
			default = new Gee.ArrayList<Host.Connection>();
		}
		public Gee.HashMap<string, Host.Connection> by_uuid {
			get;
			set;
			default = new Gee.HashMap<string, Host.Connection>();
		}
		/**
		 * Nested host tree + flat search list (not JSON).
		 */
		public Host.TreeNodes tree {
			get;
			set;
			default = new Host.TreeNodes();
		}
		public string path { get; set; default = ""; }
		/**
		 * uuid → password from Ásbrú import; drained by {@link store_pending_secrets}.
		 * Not serialized to JSON.
		 */
		public Gee.HashMap<string, string> pending_secrets {
			get;
			set;
			default = new Gee.HashMap<string, string>();
		}

		public unowned ParamSpec? find_property(string name)
		{
			return ((ObjectClass) typeof(Config).class_ref()).find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			((Object) this).set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			((Object) this).get_property(pspec.get_name(), ref val);
			return val;
		}

		public Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "by-uuid":
				case "tree":
				case "path":
				case "pending-secrets":
					return null;
				case "connections":
					var arr = new Json.Array();
					foreach (var conn in this.connections) {
						arr.add_element(Json.gobject_serialize(conn));
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.take_array(arr);
					return node;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "connections":
					this.connections.clear();
					if (property_node.get_node_type() == Json.NodeType.ARRAY) {
						var json_array = property_node.get_array();
						for (var i = 0; i < json_array.get_length(); i++) {
							var conn = Json.gobject_deserialize(typeof(Host.Connection), json_array.get_element(i)) as Host.Connection;
							if (conn == null) {
								continue;
							}
							this.connections.add(conn);
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.connections);
					return true;
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}

		/**
		 * Load ``~/.config/rooterm/connections.json``, or import Ásbrú once and write it.
		 *
		 * @return New config instance
		 * @throws GLib.Error On read / parse / write failure
		 */
		public static Config load() throws GLib.Error
		{
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "rooterm"
			);
			GLib.DirUtils.create_with_parents(dir, 0755);
			var path = GLib.Path.build_filename(dir, "connections.json");

			if (!GLib.FileUtils.test(path, GLib.FileTest.IS_REGULAR)) {
				var asbru = new Asbru.Config();
				asbru.load();
				var config = asbru.to_config();
				config.path = path;
				config.save();
				GLib.debug("imported asbru connections=%d roots=%d to %s",
					config.by_uuid.size, config.tree.size, config.path);
				return config;
			}

			var parser = new Json.Parser();
			parser.load_from_file(path);
			var config = (Config) Json.gobject_deserialize(typeof(Config), parser.get_root());
			config.path = path;
			config.tree.config = config;
			foreach (var conn in config.connections) {
				if (conn.uuid.length == 0) {
					continue;
				}
				conn.children = new Host.TreeNodes();
				config.by_uuid.set(conn.uuid, conn);
			}
			foreach (var conn in config.by_uuid.values) {
				if (conn.deleted) {
					continue;
				}
				if (conn.kind == Host.ConnectionKind.LOCAL_PATH) {
					continue;
				}
				Host.Connection? parent = null;
				if (conn.parent_uuid.length > 0 && conn.parent_uuid != "__PAC__ROOT__"
					&& config.by_uuid.has_key(conn.parent_uuid)) {
					parent = config.by_uuid.get(conn.parent_uuid);
					if (parent.deleted) {
						parent = null;
					}
				}
				config.tree.append(parent, conn);
			}
			config.tree.sort((a, b) => {
				return a.name.collate(b.name);
			});
			foreach (var conn in config.by_uuid.values) {
				conn.children.sort((a, b) => {
					return a.name.collate(b.name);
				});
			}
			GLib.debug("loaded connections=%d roots=%d from %s",
				config.by_uuid.size, config.tree.size, config.path);
			return config;
		}

		/**
		 * Store {@link pending_secrets} one-at-a-time via async libsecret on the
		 * default main context (parallel begins abandon SecretService init).
		 */
		public void store_pending_secrets()
		{
			this.store_next_pending_secret();
		}

		/**
		 * Drain one pending secret, then schedule the next on completion.
		 */
		private void store_next_pending_secret()
		{
			string? uuid = null;
			string? pass = null;
			foreach (var key in this.pending_secrets.keys) {
				uuid = key;
				pass = this.pending_secrets.get(key);
				break;
			}
			if (uuid == null || pass == null || pass.length == 0) {
				if (uuid != null) {
					this.pending_secrets.unset(uuid);
					this.store_next_pending_secret();
				}
				return;
			}
			this.pending_secrets.unset(uuid);
			var schema = new Secret.Schema(
				"org.roojs.rooterm.Connection", Secret.SchemaFlags.NONE,
				"uuid", Secret.SchemaAttributeType.STRING
			);
			var store_uuid = uuid;
			Secret.password_store.begin(
				schema,
				Secret.COLLECTION_DEFAULT,
				"RooTerm " + store_uuid,
				pass,
				null,
				(obj, res) => {
					try {
						Secret.password_store.end(res);
						GLib.debug("secret imported uuid=%s", store_uuid);
					} catch (GLib.Error e) {
						GLib.warning("secret import failed uuid=%s: %s", store_uuid, e.message);
					}
					this.store_next_pending_secret();
				},
				"uuid", store_uuid
			);
		}

		/**
		 * Write the current tree to {@link path} (no passwords).
		 * Write failures log a warning only.
		 */
		public void save()
		{
			this.connections.clear();
			var ordered = new Gee.ArrayList<Host.Connection>();
			foreach (var conn in this.by_uuid.values) {
				ordered.add(conn);
			}
			ordered.sort((a, b) => {
				return a.name.collate(b.name);
			});
			foreach (var conn in ordered) {
				this.connections.add(conn);
			}
			var generator = new Json.Generator();
			generator.set_root(Json.gobject_serialize(this));
			generator.pretty = true;
			generator.indent = 2;
			try {
				generator.to_file(this.path);
			} catch (GLib.Error e) {
				GLib.warning("config save failed: %s", e.message);
				return;
			}
			GLib.debug("saved connections=%d to %s", this.by_uuid.size, this.path);
		}
	}
}
