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
	 * Callback for staged ``lxc-ls`` results (dialog Save applies later).
	 *
	 * @param names Container names from the remote host
	 */
	public delegate void ContainerNamesCb(string[] names);

	/**
	 * Connection or group (``is_group``); JSON via {@link Json.Serializable}.
	 */
	public class Connection : Object, Json.Serializable
	{
		public string uuid { get; set; default = ""; }
		public string name { get; set; default = ""; }
		/**
		 * Search / filter label (parent prefix for LXC children); not stored / not JSON.
		 */
		public string search_name {
			owned get {
				if (this.parent != null && this.lxc_container) {
					return this.parent.name + " / " + this.name;
				}
				return this.name;
			}
		}
		public bool is_group { get; set; default = false; }
		public string parent_uuid { get; set; default = ""; }
		/**
		 * Live parent in the host tree; not JSON ({@link parent_uuid} is).
		 */
		public weak Connection? parent { get; set; default = null; }
		public string method { get; set; default = ""; }
		public string host { get; set; default = ""; }
		public int port { get; set; default = 22; }
		public string user { get; set; default = ""; }
		public string pass { get; set; default = ""; }
		public string passphrase { get; set; default = ""; }
		public string auth { get; set; default = ""; }
		public string public_key { get; set; default = ""; }
		/**
		 * Old private-key path still on the server; clear after {@link ConnDialog} remove step.
		 */
		public string retire_key { get; set; default = ""; }
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
		/**
		 * Synthetic Localhost root row (not stored in ``connections.json``).
		 */
		public bool is_local { get; set; default = false; }
		/**
		 * Ephemeral path child under Localhost for one open local PTY.
		 */
		public bool local_path { get; set; default = false; }
		/**
		 * Tab index on the Localhost {@link HostPage} for a {@link local_path} row.
		 */
		public int local_tab { get; set; default = -1; }
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
		private HostTreeNodes _children = new HostTreeNodes();
		private ulong children_sid = 0;
		/**
		 * Nested host / container rows.
		 */
		public HostTreeNodes children {
			get {
				return this._children;
			}
			set {
				if (this.children_sid != 0) {
					this._children.disconnect(this.children_sid);
				}
				this._children = value;
				this.children_sid = this._children.items_changed.connect((m, p, r, a) => {
					this.notify_property("has-children");
					this.notify_property("hide-expander");
				});
				this.notify_property("has-children");
				this.notify_property("hide-expander");
			}
		}
		/**
		 * Whether {@link children} has any rows.
		 */
		public bool has_children {
			get {
				return this._children.size > 0;
			}
		}
		/**
		 * Inverse of {@link has_children} for {@link Gtk.TreeExpander.hide_expander}.
		 */
		public bool hide_expander {
			get {
				return this._children.size == 0;
			}
		}

		construct {
			this.children_sid = this._children.items_changed.connect((m, p, r, a) => {
				this.notify_property("has-children");
				this.notify_property("hide-expander");
			});
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
				case "parent":
				case "search-name":
				case "has-children":
				case "hide-expander":
				case "is-local":
				case "local-path":
				case "local-tab":
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
		 * Discover LXC containers via a session (``lxc-ls``).
		 *
		 * With ``on_listed`` null, applies names to the tree and saves. Otherwise
		 * only invokes the callback (dialog can stage until Save). Closes the
		 * list tab after five seconds.
		 *
		 * @param window Window providing sessions / config
		 * @param on_listed Optional handler instead of applying to the tree
		 * @return The list terminal tab
		 */
		public SshTerminal refresh_containers(MainWindow window, owned ContainerNamesCb? on_listed = null)
		{
			var stream = new SshStream();
			stream.list_containers = true;
			var term = window.sessions.open(this, stream);
			term.stream.containers_found.connect((names) => {
				if (on_listed != null) {
					on_listed(names);
				} else {
					this.apply_containers(names, window);
				}
				GLib.Timeout.add_seconds(5, () => {
					term.close_tab();
					return false;
				});
			});
			return term;
		}

		/**
		 * Apply ``lxc-ls`` names: add missing children, soft-delete removed ones, save.
		 *
		 * @param names Container names from the remote host
		 * @param window Window providing config
		 */
		public void apply_containers(string[] names, MainWindow window)
		{
			GLib.debug("containers_found host=%s count=%d", this.name, names.length);
			if (names.length == 0) {
				GLib.warning("containers_found empty host=%s — skip sync", this.name);
				return;
			}
			var keep = new Gee.HashMap<string, Connection>();
			foreach (var child in this.children) {
				if (!child.lxc_container || child.deleted) {
					continue;
				}
				keep.set(child.lxc_name, child);
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
				window.config.by_uuid.set(child.uuid, child);
				window.config.tree.append(this, child);
				GLib.debug("containers_found add name=%s uuid=%s", name, child.uuid);
			}
			var gone = new Gee.ArrayList<Connection>();
			foreach (var child in this.children) {
				if (!child.lxc_container || child.deleted) {
					continue;
				}
				if (seen.contains(child.lxc_name)) {
					continue;
				}
				child.deleted = true;
				gone.add(child);
			}
			foreach (var child in gone) {
				window.config.tree.remove(child);
			}
			try {
				window.config.save();
			} catch (GLib.Error e) {
				GLib.warning("config save failed: %s", e.message);
			}
		}
	}
}
