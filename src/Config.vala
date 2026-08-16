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
	 * RooTerm settings in ``config.json``. Host tree lives on {@link MainWindow}.
	 */
	public class Config : Object, Json.Serializable
	{
		public int version { get; set; default = 1; }
		/**
		 * VTE font family. Empty = system monospace family
		 * (``org.gnome.desktop.interface`` ``monospace-font-name``, family only).
		 */
		[Description(nick = "Font family", blurb = "Monospace font family (empty = system)")]
		public string font_family { get; set; default = ""; }
		/**
		 * VTE font size in points.
		 */
		[Description(nick = "Font size", blurb = "Terminal font size in points")]
		public int font_size { get; set; default = 9; }

		/**
		 * Pango font string for VTE: resolved family + {@link font_size}.
		 * Empty {@link font_family} uses the system monospace family.
		 *
		 * @return Description like ``Ubuntu Sans Mono 9``
		 */
		public string font()
		{
			var face = this.font_family;
			if (face.length == 0) {
				face = Dialog.Fonts.system();
			}
			return "%s %d".printf(face, this.font_size);
		}

		/**
		 * {@link font} as a {@link Pango.FontDescription} for VTE ``font_desc``.
		 *
		 * @return Parsed description from {@link font}
		 */
		public Pango.FontDescription font_desc()
		{
			return Pango.FontDescription.from_string(this.font());
		}

		/**
		 * Drop-down width as percent of the monitor (1–100). Full width for now.
		 */
		[Description(nick = "Width", blurb = "Drop-down width as percent of the monitor")]
		public int width { get; set; default = 100; }
		/**
		 * Drop-down height as percent of the monitor (1–100).
		 */
		[Description(nick = "Height", blurb = "Drop-down height as percent of the monitor")]
		public int height { get; set; default = 60; }
		/**
		 * Desktop-wide show/hide (Shell media-keys / ``--toggle-key``).
		 */
		[Description(nick = "Toggle visibility", blurb = "Show or hide the drop-down")]
		public string key_toggle { get; set; default = "F12"; }
		/**
		 * Fill the monitor work area (under the Shell top bar); default ``F11``.
		 */
		[Description(nick = "Full screen", blurb = "Toggle work-area full screen")]
		public string key_fullscreen { get; set; default = "F11"; }
		/**
		 * Focus the host search entry.
		 */
		[Description(nick = "Search hosts", blurb = "Focus the host tree search")]
		public string key_search { get; set; default = "<Control><Shift>o"; }
		/**
		 * Open a new local terminal tab.
		 */
		[Description(nick = "New terminal", blurb = "Open a local terminal tab")]
		public string key_new_terminal { get; set; default = "<Control><Shift>t"; }
		/**
		 * Open a new SSH tab for the focused host.
		 */
		[Description(nick = "New SSH", blurb = "Open an SSH tab for the focused host")]
		public string key_new_ssh { get; set; default = "<Control><Shift>s"; }
		/**
		 * Close the current terminal tab.
		 */
		[Description(nick = "Close terminal", blurb = "Close the current tab")]
		public string key_close_terminal { get; set; default = "<Control><Shift>w"; }
		/**
		 * Select the previous tab.
		 */
		[Description(nick = "Previous tab", blurb = "Select the previous tab")]
		public string key_prev_tab { get; set; default = "<Control><Shift>Left"; }
		/**
		 * Select the next tab.
		 */
		[Description(nick = "Next tab", blurb = "Select the next tab")]
		public string key_next_tab { get; set; default = "<Control><Shift>Right"; }
		/**
		 * Select all in the focused VTE.
		 */
		[Description(nick = "Select all", blurb = "Select all terminal text")]
		public string key_select_all { get; set; default = "<Control><Shift>a"; }
		/**
		 * Copy from the focused VTE.
		 */
		[Description(nick = "Copy", blurb = "Copy selected terminal text")]
		public string key_copy { get; set; default = "<Control><Shift>c"; }
		/**
		 * Paste into the focused VTE.
		 */
		[Description(nick = "Paste", blurb = "Paste into the terminal")]
		public string key_paste { get; set; default = "<Control><Shift>v"; }
		/**
		 * Open preferences.
		 */
		[Description(nick = "Preferences", blurb = "Open the preferences window")]
		public string key_preferences { get; set; default = "<Control>comma"; }
		/**
		 * Reset the focused VTE.
		 */
		[Description(nick = "Reset terminal", blurb = "Reset the current terminal")]
		public string key_reset_terminal { get; set; default = "<Control><Shift>k"; }
		/**
		 * Quit the application.
		 */
		[Description(nick = "Quit", blurb = "Quit Roo Term")]
		public string key_quit { get; set; default = "<Control><Shift>q"; }
		/**
		 * VTE background opacity percent (10–100). Host chrome stays opaque.
		 */
		[Description(nick = "Opacity", blurb = "Terminal background opacity percent")]
		public int opacity { get; set; default = 100; }
		/**
		 * Horizontal placement on the monitor: ``left``, ``centre``, or ``right``.
		 */
		[Description(nick = "Placement", blurb = "Left, centre, or right on the monitor")]
		public string placement { get; set; default = "centre"; }
		/**
		 * Selected VTE theme name (unique within {@link theme_category}).
		 * Empty = first theme in the Black catalogue file.
		 */
		[Description(nick = "Foreground theme", blurb = "Terminal colour theme name")]
		public string theme_name { get; set; default = ""; }
		/**
		 * Background category for {@link theme_name}: ``black``, ``dark-grey``,
		 * ``dark``, ``off-white``, or ``white``.
		 */
		[Description(nick = "Background colour", blurb = "Theme background category")]
		public string theme_category { get; set; default = "black"; }
		/**
		 * Stock VTE theme catalogue ({@link Themes.load}). Not serialized.
		 */
		public Themes themes {
			get;
			set;
			default = new Themes();
		}
		/**
		 * Flat host list placeholder so JSON-GLib sees the ``connections`` key
		 * (sets {@link need_migrate}). Not filled here; migrate re-reads the file.
		 * Not written to ``config.json``.
		 */
		public Gee.ArrayList<Host.Connection> connections {
			get;
			set;
			default = new Gee.ArrayList<Host.Connection>();
		}
		/**
		 * True when settings JSON contained ``connections`` — caller runs
		 * {@link Host.TreeNodes.load}, which migrates when set.
		 * Not serialized.
		 */
		public bool need_migrate { get; set; default = false; }
		/**
		 * uuid → password from Ásbrú import; drained by {@link store_pending_secrets}.
		 * Not serialized.
		 */
		public Gee.HashMap<string, string> pending_secrets {
			get;
			set;
			default = new Gee.HashMap<string, string>();
		}
		/**
		 * On show, restore the last tab used on this GNOME workspace.
		 */
		[Description(nick = "Remember tab per workspace", blurb = "On show, restore the last tab used on this desktop")]
		public bool remember_workspace_tab { get; set; default = true; }
		/**
		 * Workspace index → {@link Host.Connection.uuid} (written to ``config.json``).
		 */
		public Gee.HashMap<int, string> workspace_uuids {
			get;
			set;
			default = new Gee.HashMap<int, string>();
		}
		/**
		 * Workspace index → live {@link Host.Connection}. Runtime only — not serialized.
		 */
		public Gee.HashMap<int, Host.Connection> workspace_tabs {
			get;
			set;
			default = new Gee.HashMap<int, Host.Connection>();
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
				case "connections":
				case "pending-secrets":
				case "need-migrate":
				case "themes":
				case "workspace-tabs":
					return null;
				case "workspace-uuids":
					var obj = new Json.Object();
					foreach (var index in this.workspace_uuids.keys) {
						obj.set_string_member(
							index.to_string(), this.workspace_uuids.get(index)
						);
					}
					var node = new Json.Node(Json.NodeType.OBJECT);
					node.take_object(obj);
					return node;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "connections":
					this.need_migrate = true;
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.connections);
					return true;
				case "workspace-uuids":
					this.workspace_uuids.clear();
					value = Value(typeof(Gee.HashMap));
					value.set_object(this.workspace_uuids);
					if (property_node.get_node_type() != Json.NodeType.OBJECT) {
						return true;
					}
					var obj = property_node.get_object();
					foreach (var name in obj.get_members()) {
						this.workspace_uuids.set(
							int.parse(name), obj.get_string_member(name)
						);
					}
					return true;
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}

		/**
		 * Load ``config.json`` (or legacy combined ``connections.json``) chrome only.
		 * Sets {@link need_migrate} when a flat ``connections`` key is present.
		 * Failures log a warning and return an empty config.
		 *
		 * @return New config instance
		 */
		public static Config load()
		{
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "rooterm"
			);
			GLib.DirUtils.create_with_parents(dir, 0755);
			var path = GLib.Path.build_filename(dir, "connections.json");
			var config_path = GLib.Path.build_filename(dir, "config.json");

			if (!GLib.FileUtils.test(config_path, GLib.FileTest.IS_REGULAR)
					&& !GLib.FileUtils.test(path, GLib.FileTest.IS_REGULAR)) {
				return new Config();
			}

			var open_path = GLib.FileUtils.test(config_path, GLib.FileTest.IS_REGULAR)
				? config_path : path;
			try {
				string contents;
				GLib.FileUtils.get_contents(open_path, out contents);
				return (Config) Json.gobject_from_data(typeof(Config), contents);
			} catch (GLib.Error e) {
				GLib.warning("config load failed: %s", e.message);
				return new Config();
			}
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
		 * Wire chrome ``notify`` handlers onto ``window`` (geometry + ``key_*``).
		 * Opacity / font apply on VTE ({@link Terminal.Base}).
		 *
		 * @param window Main window to resize / rebind
		 */
		public void connect(MainWindow window)
		{
			this.notify["height"].connect(() => {
				if (!window.is_docked || window.fullscreen) {
					return;
				}
				window.set_default_size(
					window.monitor_geo.width * this.width / 100,
					window.monitor_geo.height * this.height / 100
				);
				window.dbus.redock(window.fullscreen);
			});
			this.notify["width"].connect(() => {
				if (!window.is_docked || window.fullscreen) {
					return;
				}
				window.set_default_size(
					window.monitor_geo.width * this.width / 100,
					window.monitor_geo.height * this.height / 100
				);
				window.dbus.redock(window.fullscreen);
			});
			this.notify["placement"].connect(() => {
				if (!window.is_docked || window.fullscreen) {
					return;
				}
				window.dbus.redock(window.fullscreen);
			});
			this.notify.connect((_, pspec) => {
				if (!pspec.name.has_prefix("key-")) {
					return;
				}
				var app = window.application as Application;
				if (app == null) {
					return;
				}
				var value = Value(typeof(string));
				((GLib.Object) this).get_property(pspec.name, ref value);
				var accel = value.get_string();
				switch (pspec.name) {
					case "key-toggle":
						app.set_accels_for_action("win.toggle", { accel });
						try {
							window.shell.ensure_toggle_binding(accel);
						} catch (GLib.Error e) {
							GLib.warning("toggle binding: %s", e.message);
						}
						break;

					case "key-fullscreen":
						app.set_accels_for_action("win.fullscreen", { accel });
						break;

					case "key-search":
						app.set_accels_for_action("win.search", { accel });
						break;

					case "key-new-terminal":
						app.set_accels_for_action("win.new-terminal", { accel });
						break;

					case "key-new-ssh":
						app.set_accels_for_action("win.new-ssh", { accel });
						break;

					case "key-close-terminal":
						app.set_accels_for_action("win.close-terminal", { accel });
						break;

					case "key-prev-tab":
						app.set_accels_for_action("win.prev-tab", { accel });
						break;

					case "key-next-tab":
						app.set_accels_for_action("win.next-tab", { accel });
						break;

					case "key-select-all":
						app.set_accels_for_action("win.select-all", { accel });
						break;

					case "key-copy":
						app.set_accels_for_action("win.copy", { accel });
						break;

					case "key-paste":
						app.set_accels_for_action("win.paste", { accel });
						break;

					case "key-preferences":
						app.set_accels_for_action("win.preferences", { accel });
						break;

					case "key-reset-terminal":
						app.set_accels_for_action("win.reset-terminal", { accel });
						break;

					case "key-quit":
						app.set_accels_for_action("win.quit", { accel });
						break;
				}
			});
		}

		/**
		 * Write ``config.json`` only (chrome / preferences). Hosts: {@link Host.TreeNodes.save}.
		 * Write failures log a warning only.
		 */
		public void save()
		{
			var config_path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "rooterm", "config.json"
			);
			try {
				GLib.FileUtils.set_contents(
					config_path, Json.gobject_to_data(this, null)
				);
			} catch (GLib.Error e) {
				GLib.warning("config save failed: %s", e.message);
				return;
			}
			GLib.debug("saved config.json");
		}
	}
}
