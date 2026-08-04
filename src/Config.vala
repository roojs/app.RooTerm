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
					return null;
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
