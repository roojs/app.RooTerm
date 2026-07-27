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
	 * Connection or group (``is_group``); JSON via {@link Json.Serializable}.
	 */
	public class Connection : Object, Json.Serializable
	{
		public string uuid { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public bool is_group { get; set; default = false; }
		public string parent_uuid { get; set; default = ""; }
		public string method { get; set; default = ""; }
		public string host { get; set; default = ""; }
		public int port { get; set; default = 22; }
		public string user { get; set; default = ""; }
		public string pass { get; set; default = ""; }
		public string passphrase { get; set; default = ""; }
		public string auth { get; set; default = ""; }
		public string public_key { get; set; default = ""; }
		public string options { get; set; default = ""; }
		public bool deleted { get; set; default = false; }
		/**
		 * After shell login, run ``sudo -i`` and feed the connection password.
		 */
		public bool sudo_after_login { get; set; default = false; }
		/**
		 * Host may have LXC containers (refresh / children).
		 */
		public bool lxc_host { get; set; default = false; }
		/**
		 * This row is an LXC container under an SSH host (not a separate SSH target).
		 */
		public bool lxc_container { get; set; default = false; }
		/**
		 * Container name for ``lxc-console -n`` (on the host or this child row).
		 */
		public string lxc_name { get; set; default = ""; }
		public Gee.ArrayList<Forward> forwards {
			get;
			set;
			default = new Gee.ArrayList<Forward>();
		}
		public int open_count { get; set; default = 0; }
		public int active_tab { get; set; default = -1; }
		public Gee.ArrayList<string> tab_titles {
			get;
			set;
			default = new Gee.ArrayList<string>();
		}
		/**
		 * Per-tab {@link SessionState} parallel to open tabs (not serialized).
		 */
		public Gee.ArrayList<SessionState> tab_states {
			get;
			set;
			default = new Gee.ArrayList<SessionState>();
		}
		public Gee.ArrayList<Connection> children {
			get;
			set;
			default = new Gee.ArrayList<Connection>();
		}

		public unowned ParamSpec? find_property(string name)
		{
			return ((ObjectClass) typeof(Connection).class_ref()).find_property(name);
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
				case "pass":
				case "passphrase":
				case "open-count":
				case "active-tab":
				case "tab-titles":
				case "tab-states":
				case "children":
					return null;
				case "forwards":
					var arr = new Json.Array();
					foreach (var fwd in this.forwards) {
						arr.add_element(Json.gobject_serialize(fwd));
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
			if (property_name != "forwards") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			this.forwards.clear();
			if (property_node.get_node_type() == Json.NodeType.ARRAY) {
				var json_array = property_node.get_array();
				for (var i = 0; i < json_array.get_length(); i++) {
					var fwd = Json.gobject_deserialize(typeof(Forward), json_array.get_element(i)) as Forward;
					if (fwd == null) {
						continue;
					}
					this.forwards.add(fwd);
				}
			}
			value = Value(typeof(Gee.ArrayList));
			value.set_object(this.forwards);
			return true;
		}

		/**
		 * Discover LXC containers via a session (``lxc-ls``) and sync child rows.
		 *
		 * @param window Window providing sessions / config / host reload
		 */
		public void refresh_containers(MainWindow window)
		{
			var stream = new SshStream();
			stream.list_containers = true;
			var term = window.sessions.open(this, stream);
			term.stream.containers_found.connect((names) => {
				this.on_containers_found(names, window);
			});
		}

		/**
		 * Apply ``lxc-ls`` names: add missing children, soft-delete removed ones, save.
		 *
		 * @param names Container names from the remote host
		 * @param window Window providing config / host reload
		 */
		private void on_containers_found(string[] names, MainWindow window)
		{
			var keep = new Gee.HashMap<string, Connection>();
			foreach (var child in this.children) {
				if (child.lxc_container && !child.deleted) {
					keep.set(child.lxc_name, child);
				}
			}
			var seen = new Gee.HashSet<string>();
			foreach (var name in names) {
				if (name.length == 0) {
					continue;
				}
				if (!GLib.Regex.match_simple("^[A-Za-z0-9][A-Za-z0-9_.-]*$", name, 0, 0)) {
					continue;
				}
				seen.add(name);
				if (keep.has_key(name)) {
					continue;
				}
				var child = new Connection() {
					uuid = GLib.Uuid.string_random(),
					name = name,
					parent_uuid = this.uuid,
					host = this.host,
					port = this.port,
					user = this.user,
					auth = this.auth,
					public_key = this.public_key,
					options = this.options,
					sudo_after_login = this.sudo_after_login,
					lxc_container = true,
					lxc_name = name
				};
				this.children.add(child);
				window.config.by_uuid.set(child.uuid, child);
			}
			foreach (var child in this.children) {
				if (!child.lxc_container || child.deleted) {
					continue;
				}
				if (seen.contains(child.lxc_name)) {
					continue;
				}
				child.deleted = true;
			}
			try {
				window.config.save();
			} catch (GLib.Error e) {
				GLib.warning("config save failed: %s", e.message);
			}
			window.host_tree.fill(window.config);
			window.host_search.fill(window.config);
		}
	}
}
