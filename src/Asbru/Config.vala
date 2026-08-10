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

namespace RooTerm.Asbru
{
	/**
	 * Loads Ásbrú ``asbru.yml`` into a {@link Host.Connection} tree (libyaml).
	 */
	public class Config
	{
		public Gee.HashMap<string, Host.Connection> by_uuid {
			get;
			set;
			default = new Gee.HashMap<string, Host.Connection>();
		}
		public Gee.ArrayList<Host.Connection> roots {
			get;
			set;
			default = new Gee.ArrayList<Host.Connection>();
		}
		public string path = "";
		/**
		 * Global ``defaults.terminal font`` (e.g. ``Monospace 9``).
		 */
		public string terminal_font = "Monospace 9";

		/**
		 * Whether the default Ásbrú file ``~/.config/asbru/asbru.yml`` exists.
		 */
		public bool exists()
		{
			var p = this.path.length > 0 ? this.path : GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "asbru", "asbru.yml"
			);
			return GLib.FileUtils.test(p, GLib.FileTest.IS_REGULAR);
		}

		/**
		 * Load config from the default Ásbrú path or an override.
		 * Failures log a warning and leave an empty map.
		 *
		 * @param config_path Optional path; empty uses ``~/.config/asbru/asbru.yml``
		 */
		public void load(string config_path = "")
		{
			this.path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "asbru", "asbru.yml"
			);
			if (config_path.length > 0) {
				this.path = config_path;
			}

			this.by_uuid.clear();
			this.roots.clear();

			GLib.Bytes bytes;
			try {
				bytes = GLib.File.new_for_path(this.path).load_bytes(null, null);
			} catch (GLib.Error e) {
				GLib.warning("asbru load failed: %s", e.message);
				return;
			}

			unowned uint8[] data = bytes.get_data();
			var parser = Yaml.Parser();
			parser.set_input_string(data);

			var at_root = false;
			var in_defaults = false;
			var in_environments = false;
			var in_connection = false;
			var skip_depth = 0;
			var want_key = true;
			var key = "";
			var uuid = "";
			var fields = new Gee.HashMap<string, string>();

			Yaml.Event event = {};
			while (parser.parse(out event) == 1) {
				if (event.type == Yaml.EventType.STREAM_END) {
					break;
				}

				if (skip_depth > 0) {
					if (event.type == Yaml.EventType.MAPPING_START || event.type == Yaml.EventType.SEQUENCE_START) {
						skip_depth++;
						continue;
					}
					if (event.type == Yaml.EventType.MAPPING_END || event.type == Yaml.EventType.SEQUENCE_END) {
						skip_depth--;
						want_key = skip_depth == 0 ? true : want_key;
						continue;
					}
					continue;
				}

				switch (event.type) {
					case Yaml.EventType.MAPPING_START:
						if (!at_root && !in_environments && !in_connection && !in_defaults) {
							at_root = true;
							want_key = true;
							continue;
						}
						if (at_root && !in_environments && !in_connection && !in_defaults && key == "defaults") {
							in_defaults = true;
							want_key = true;
							continue;
						}
						if (at_root && !in_environments && !in_connection && !in_defaults && key == "environments") {
							in_environments = true;
							want_key = true;
							continue;
						}
						if (in_environments && !in_connection) {
							uuid = key;
							in_connection = true;
							fields = new Gee.HashMap<string, string>();
							want_key = true;
							continue;
						}
						skip_depth = 1;
						continue;

					case Yaml.EventType.MAPPING_END:
						if (in_defaults) {
							in_defaults = false;
							want_key = true;
							continue;
						}
						if (!in_connection && in_environments) {
							in_environments = false;
							want_key = true;
							continue;
						}
						if (!in_connection) {
							at_root = false;
							continue;
						}
						if (uuid == "__PAC__ROOT__") {
							in_connection = false;
							want_key = true;
							continue;
						}
						var group = fields.has_key("_is_group") ? fields.get("_is_group") : "";
						var port = 22;
						if (fields.has_key("port") && fields.get("port").length > 0) {
							port = int.parse(fields.get("port"));
						}
						var conn = new Host.Connection() {
							uuid = uuid,
							name = fields.has_key("name") ? fields.get("name").strip() : "",
							parent_uuid = fields.has_key("parent") ? fields.get("parent").strip() : "",
							method = fields.has_key("method") ? fields.get("method").strip() : "",
							host = fields.has_key("ip") ? fields.get("ip").strip() : "",
							user = fields.has_key("user") ? fields.get("user").strip() : "",
							auth = fields.has_key("auth type") ? fields.get("auth type").strip() : "",
							public_key = fields.has_key("public key") ? fields.get("public key").strip() : "",
							options = fields.has_key("options") ? fields.get("options").strip() : "",
							kind = (group == "1" || group.down() == "true") ? Host.ConnectionKind.GROUP : Host.ConnectionKind.HOST,
							port = port,
							pass = Cipher.decrypt_hex(fields.has_key("pass") ? fields.get("pass") : ""),
							passphrase = Cipher.decrypt_hex(fields.has_key("passphrase") ? fields.get("passphrase") : "")
						};
						if (conn.kind != Host.ConnectionKind.GROUP && conn.method != "SSH" && conn.method.length > 0) {
							GLib.debug("skip non-ssh method=%s name=%s", conn.method, conn.name);
							in_connection = false;
							want_key = true;
							continue;
						}
						this.by_uuid.set(uuid, conn);
						in_connection = false;
						want_key = true;
						continue;

					case Yaml.EventType.SEQUENCE_START:
						skip_depth = 1;
						continue;

					case Yaml.EventType.SCALAR:
						var val = event.data_scalar_value != null ? event.data_scalar_value : "";
						if (val == "~" || val == "null") {
							val = "";
						}
						if (want_key) {
							key = val;
							want_key = false;
							continue;
						}
						if (in_defaults) {
							if (key == "terminal font" && val.length > 0) {
								this.terminal_font = val;
							}
							want_key = true;
							continue;
						}
						if (in_connection) {
							fields.set(key, val);
						}
						want_key = true;
						continue;

					default:
						continue;
				}
			}

			foreach (var conn in this.by_uuid.values) {
				if (conn.parent_uuid.length == 0 || conn.parent_uuid == "__PAC__ROOT__") {
					this.roots.add(conn);
					continue;
				}
				if (!this.by_uuid.has_key(conn.parent_uuid)) {
					this.roots.add(conn);
					continue;
				}
			}

			this.roots.sort((a, b) => {
				return a.name.collate(b.name);
			});

			GLib.debug("loaded connections=%d roots=%d font=%s from %s",
				this.by_uuid.size, this.roots.size, this.terminal_font, this.path);
		}

		/**
		 * Build a RooTerm {@link RooTerm.Config} from this loaded Ásbrú tree
		 * (font + pending secrets). Host nest: {@link to_host_tree}.
		 *
		 * Passwords are queued on {@link RooTerm.Config.pending_secrets} for async
		 * libsecret store after the UI main loop is running (sync store deadlocks
		 * on the keyring ACL prompt).
		 *
		 * @return New config ready to save
		 */
		public RooTerm.Config to_config()
		{
			var config = new RooTerm.Config();
			var desc = Pango.FontDescription.from_string(this.terminal_font);
			if (desc.get_family() != null && desc.get_family().length > 0) {
				config.font_family = desc.get_family();
			}
			if (desc.get_size() > 0) {
				config.font_size = desc.get_size() / Pango.SCALE;
			}
			foreach (var conn in this.by_uuid.values) {
				if (conn.pass.length > 0) {
					config.pending_secrets.set(conn.uuid, conn.pass);
				}
			}
			return config;
		}

		/**
		 * Build a host nest from Ásbrú rows (auth remap, forwards, nest).
		 *
		 * @return New tree ready to save / assign on the window
		 */
		public Host.TreeNodes to_host_tree()
		{
			var tree = new Host.TreeNodes();
			foreach (var conn in this.by_uuid.values) {
				if (conn.auth == "publickey") {
					conn.auth = "ssh_key";
				}
				if (conn.auth == "userpass") {
					conn.auth = "password";
				}
				conn.pass = "";
				conn.passphrase = "";
				this.take_forwards(conn);
				conn.children = new Host.TreeNodes();
				tree.by_uuid.set(conn.uuid, conn);
			}
			foreach (var conn in this.by_uuid.values) {
				Host.Connection? parent = null;
				if (conn.parent_uuid.length > 0 && conn.parent_uuid != "__PAC__ROOT__"
					&& tree.by_uuid.has_key(conn.parent_uuid)) {
					parent = tree.by_uuid.get(conn.parent_uuid);
				}
				tree.append(parent, conn);
			}
			return tree;
		}

		/**
		 * Peel Ásbrú ``-L`` / ``-Lspec`` tokens out of ``conn.options`` into {@link Host.Connection.forwards}.
		 * Import-only; RooTerm JSON already stores forwards separately.
		 *
		 * @param conn Host.Connection whose Ásbrú options may contain forwards
		 */
		private void take_forwards(Host.Connection conn)
		{
			if (conn.options.index_of("-L") < 0) {
				return;
			}
			string[] kept = {};
			var tokens = conn.options.strip().split_set(" \t");
			for (var i = 0; i < tokens.length; i++) {
				var tok = tokens[i];
				if (tok.length == 0) {
					continue;
				}
				var spec = "";
				if (tok == "-L" && i + 1 < tokens.length) {
					spec = tokens[i + 1];
					i++;
				} else if (tok.has_prefix("-L") && tok.length > 2) {
					spec = tok.substring(2);
				} else {
					kept += tok;
					continue;
				}
				var parts = spec.split(":");
				if (parts.length < 3) {
					parts = spec.split("/");
				}
				if (parts.length == 3) {
					conn.forwards.add(new Host.Forward() {
						local_host = "127.0.0.1",
						local_port = int.parse(parts[0]),
						remote_host = parts[1],
						remote_port = int.parse(parts[2])
					});
					continue;
				}
				if (parts.length >= 4) {
					conn.forwards.add(new Host.Forward() {
						local_host = parts[0],
						local_port = int.parse(parts[1]),
						remote_host = parts[2],
						remote_port = int.parse(parts[3])
					});
					continue;
				}
				kept += "-L";
				kept += spec;
			}
			conn.options = string.joinv(" ", kept).strip();
		}
	}
}
