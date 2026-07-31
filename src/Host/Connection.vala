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
	 * Host.Tree / config row role for a {@link Connection}.
	 *
	 * Stored as an integer in ``connections.json``. **Order is permanent** —
	 * never insert or reorder members (that remaps old rows). Always **append**
	 * new values at the end.
	 */
	public enum ConnectionKind
	{
		HOST,
		GROUP,
		LOCAL,
		LOCAL_PATH,
		LXC
	}

	/**
	 * Connection or group ({@link ConnectionKind}); JSON via {@link Json.Serializable}.
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
				if (this.parent != null && this.kind == ConnectionKind.LXC) {
					return this.parent.name + " / " + this.name;
				}
				return this.name;
			}
		}
		/**
		 * Row role (host, group, localhost, path, LXC container).
		 */
		public ConnectionKind kind { get; set; default = ConnectionKind.HOST; }
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
		 * Old private-key path still on the server; clear after {@link Dialog.Connection} remove step.
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
		 * Container name for ``lxc-console -n`` (on the host or this child row).
		 */
		public string lxc_name { get; set; default = ""; }
		public Gee.ArrayList<Forward> forwards {
			get;
			set;
			default = new Gee.ArrayList<Forward>();
		}
		/**
		 * Open {@link Terminal.Base} tabs for this host (tree session marks bind here).
		 */
		public GLib.ListStore sessions {
			get;
			set;
			default = new GLib.ListStore(typeof(Terminal.Base));
		}
		private Host.TreeNodes _children = new Host.TreeNodes();
		private ulong children_sid = 0;
		/**
		 * Nested host / container rows.
		 */
		public Host.TreeNodes children {
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
		/**
		 * Host-tree row icon name (not JSON).
		 */
		public string tree_icon {
			owned get {
				switch (this.kind) {
					case ConnectionKind.GROUP:
					case ConnectionKind.LOCAL_PATH:
						return "folder";

					case ConnectionKind.LOCAL:
						return "computer";

					case ConnectionKind.LXC:
						return "drive-harddisk";

					case ConnectionKind.HOST:
						if (this.sudo_after_login) {
							return "security-high";
						}
						return "video-display";
				}
				return "video-display";
			}
		}

		construct {
			this.children_sid = this._children.items_changed.connect((m, p, r, a) => {
				this.notify_property("has-children");
				this.notify_property("hide-expander");
			});
			this.notify.connect((o, pspec) => {
				switch (pspec.name) {
					case "name":
						this.notify_property("search-name");
						break;

					case "kind":
					case "sudo-after-login":
						this.notify_property("tree-icon");
						break;
				}
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
				case "sessions":
				case "children":
				case "parent":
				case "search-name":
				case "has-children":
				case "hide-expander":
				case "tree-icon":
				case "local-tab":
					return null;

				case "kind":
					var kind_node = new Json.Node(Json.NodeType.VALUE);
					kind_node.set_int((int64) this.kind);
					return kind_node;

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
			switch (property_name) {
				case "kind":
					this.kind = (ConnectionKind) property_node.get_int();
					value = Value(typeof(ConnectionKind));
					value.set_enum(this.kind);
					return true;

				case "forwards":
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

				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}

		/**
		 * Discover LXC containers via {@link FetchHosts}.
		 *
		 * @param window Window providing sessions / config
		 * @return Parsed container names from ``lxc-ls``
		 */
		public async string[] refresh_containers(MainWindow window) throws JobError
		{
			var job = new FetchHosts(window, this);
			try {
				yield job.run();
				job.terminal.close_in(0);
				return job.container_names;
			} catch (JobError e) {
				job.terminal.close_in(30);
				throw e;
			}
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
				if (child.kind != ConnectionKind.LXC || child.deleted) {
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
					kind = ConnectionKind.LXC,
					lxc_name = name
				};
				window.config.by_uuid.set(child.uuid, child);
				window.config.tree.append(this, child);
				GLib.debug("containers_found add name=%s uuid=%s", name, child.uuid);
			}
			var gone = new Gee.ArrayList<Connection>();
			foreach (var child in this.children) {
				if (child.kind != ConnectionKind.LXC || child.deleted) {
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
