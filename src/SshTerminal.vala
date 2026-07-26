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
	 * VTE terminal for one SSH session on a {@link Connection}.
	 */
	public class SshTerminal : Gtk.Box
	{
		public Connection connection;
		public Vte.Terminal terminal;
		public string cwd = "";
		private string window_title = "";
		/**
		 * Last shell/mysql-style prompt line scraped from the screen (OSC often missing over SSH).
		 */
		private string prompt_hint = "";
		private uint prompt_timeout = 0;
		private bool sent_secret = false;
		private GLib.FileStream? session_log = null;
		private bool hide_input = false;
		/**
		 * Absolute VTE row to read for the next ``#`` log line (``-1`` = not waiting).
		 */
		private long log_line = -1;

		/**
		 * Emitted when the SSH child process exits.
		 */
		public signal void exited();

		/**
		 * Emitted when {@link cwd} (and thus {@link label}) changes.
		 */
		public signal void label_changed();

		/**
		 * Build a scrolled VTE for ``connection`` (call {@link spawn} to start SSH).
		 *
		 * @param connection Host to open
		 * @param font Pango font string (Ásbrú ``terminal font``)
		 */
		public SshTerminal(Connection connection, string font = "Monospace 9")
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
			this.connection = connection;
			this.terminal = new Vte.Terminal() {
				hexpand = true,
				vexpand = true,
				font_desc = Pango.FontDescription.from_string(font)
			};
			this.terminal.set_size(80, 24);
			this.append(new Gtk.ScrolledWindow() {
				child = this.terminal,
				hexpand = true,
				vexpand = true
			});

			var shortcuts = new Gtk.ShortcutController() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
				scope = Gtk.ShortcutScope.LOCAL
			};
			shortcuts.add_shortcut(new Gtk.Shortcut(
				Gtk.ShortcutTrigger.parse_string("<Control><Shift>c"),
				new Gtk.CallbackAction(() => {
					this.terminal.copy_clipboard_format(Vte.Format.TEXT);
					return true;
				})
			));
			shortcuts.add_shortcut(new Gtk.Shortcut(
				Gtk.ShortcutTrigger.parse_string("<Control><Shift>v"),
				new Gtk.CallbackAction(() => {
					this.terminal.paste_clipboard();
					return true;
				})
			));
			this.terminal.add_controller(shortcuts);

			this.terminal.child_exited.connect((status) => {
				var exit_code = (status >> 8) & 0xff;
				GLib.debug("ssh child exited status=%d exit=%d name=%s", status, exit_code, this.connection.name);
				var done = "\r\n[ssh exited: " + exit_code.to_string() + " — closing in 10s]\r\n";
				this.terminal.feed(done.data);
				if (this.session_log != null) {
					this.session_log.printf("\n# exited %d\n", exit_code);
					this.session_log.flush();
					this.session_log = null;
				}
				this.exited();
			});
			this.terminal.termprop_changed.connect((prop) => {
				if (prop == Vte.TERMPROP_XTERM_TITLE) {
					size_t size;
					var title = this.terminal.dup_termprop_string(prop, out size);
					this.window_title = title != null ? title : "";
					this.label_changed();
					return;
				}
				if (prop != Vte.TERMPROP_CURRENT_DIRECTORY_URI) {
					return;
				}
				var uri = this.terminal.ref_termprop_uri(prop);
				if (uri == null) {
					return;
				}
				var path = GLib.File.new_for_uri(uri.to_string()).get_path();
				if (path == null) {
					return;
				}
				this.cwd = path;
				this.label_changed();
			});
			this.terminal.window_title_changed.connect(() => {
				var title = this.terminal.get_window_title();
				this.window_title = title != null ? title : "";
				this.label_changed();
			});
			this.terminal.commit.connect((text, size) => {
				if (this.session_log == null) {
					return;
				}
				if (this.hide_input) {
					if (text.index_of_char('\n') < 0 && text.index_of_char('\r') < 0) {
						return;
					}
					this.hide_input = false;
					this.session_log.puts("[password omitted]\n");
					this.session_log.flush();
					long col;
					long row;
					this.terminal.get_cursor_position(out col, out row);
					this.log_line = row + 1;
					return;
				}
				this.session_log.puts(text);
				this.session_log.flush();
				if (text.index_of_char('\n') >= 0 || text.index_of_char('\r') >= 0) {
					long col;
					long row;
					this.terminal.get_cursor_position(out col, out row);
					this.log_line = row + 1;
				}
			});
			this.terminal.contents_changed.connect(() => {
				if (this.prompt_timeout != 0) {
					return;
				}
				this.prompt_timeout = GLib.Timeout.add(120, () => {
					this.prompt_timeout = 0;
					long col;
					long row;
					this.terminal.get_cursor_position(out col, out row);
					size_t len;
					var raw = this.terminal.get_text_range_format(Vte.Format.TEXT, row, 0, row, col, out len);
					var last = raw != null ? raw.replace("\r", "").strip() : "";
					if (last.length == 0 || last.length > 240) {
						return false;
					}
					if (GLib.Regex.match_simple("(password|passphrase).*:\\s*$", last, GLib.RegexCompileFlags.CASELESS, 0)) {
						return false;
					}
					var is_prompt = GLib.Regex.match_simple("^[^\\s@]+@[^\\s:]+:.*[#$]\\s*$", last, 0, 0)
						|| GLib.Regex.match_simple("^(MariaDB|mysql|sqlite3?|postgres|plsql)\\b.*>\\s*$", last, GLib.RegexCompileFlags.CASELESS, 0)
						|| ((last.has_suffix("$") || last.has_suffix("#") || last.has_suffix("%")) && last.length < 160);
					if (!is_prompt || last == this.prompt_hint) {
						return false;
					}
					this.prompt_hint = last;
					this.label_changed();
					return false;
				});
			});
			this.terminal.contents_changed.connect(() => {
				if (this.hide_input) {
					return;
				}
				long col;
				long row;
				this.terminal.get_cursor_position(out col, out row);
				size_t len;
				var raw = this.terminal.get_text_range_format(Vte.Format.TEXT, row, 0, row, col, out len);
				var line = raw != null ? raw.replace("\r", "").strip() : "";
				if (line.length == 0) {
					return;
				}
				if (!GLib.Regex.match_simple(
					"(password|passphrase|\\[sudo\\]\\s*password).*:\\s*$",
					line,
					GLib.RegexCompileFlags.CASELESS,
					0
				)) {
					return;
				}
				this.hide_input = true;
				if (this.sent_secret) {
					return;
				}
				if (GLib.Regex.match_simple("passphrase.*:\\s*$", line, GLib.RegexCompileFlags.CASELESS, 0)
					&& this.connection.passphrase.length > 0
					&& this.connection.auth != "manual") {
					this.sent_secret = true;
					this.hide_input = false;
					var passphrase = this.connection.passphrase + "\n";
					this.terminal.feed_child(passphrase.data);
					GLib.debug("fed passphrase name=%s", this.connection.name);
					return;
				}
				if (GLib.Regex.match_simple("password:\\s*$", line, GLib.RegexCompileFlags.CASELESS, 0)
					&& this.connection.auth != "manual"
					&& this.connection.auth != "ssh_key"
					&& this.connection.auth != "publickey") {
					if (this.connection.pass.length == 0) {
						try {
							var pass = Secret.password_lookup_sync(
								new Secret.Schema(
									"org.roojs.rooterm.Connection",
									Secret.SchemaFlags.NONE,
									"uuid", Secret.SchemaAttributeType.STRING
								),
								null,
								"uuid", this.connection.uuid
							);
							this.connection.pass = pass != null ? pass : "";
						} catch (GLib.Error e) {
							GLib.warning("secret load failed uuid=%s: %s", this.connection.uuid, e.message);
						}
					}
					if (this.connection.pass.length == 0) {
						return;
					}
					this.sent_secret = true;
					this.hide_input = false;
					var password = this.connection.pass + "\n";
					this.terminal.feed_child(password.data);
					GLib.debug("fed password name=%s", this.connection.name);
				}
			});
			this.terminal.contents_changed.connect(() => {
				if (this.session_log == null || this.log_line < 0 || this.hide_input) {
					return;
				}
				long col;
				long row;
				this.terminal.get_cursor_position(out col, out row);
				if (row < this.log_line) {
					return;
				}
				var end_col = row > this.log_line ? this.terminal.get_column_count() : col;
				if (end_col <= 0) {
					return;
				}
				size_t len;
				var raw = this.terminal.get_text_range_format(
					Vte.Format.TEXT, this.log_line, 0, this.log_line, end_col, out len
				);
				var line = raw != null ? raw.replace("\r", "").strip() : "";
				if (line.length == 0) {
					if (row > this.log_line) {
						this.log_line = -1;
					}
					return;
				}
				this.log_line = -1;
				if (line.length > 500 || line.index_of("\x1b") >= 0) {
					return;
				}
				if (GLib.Regex.match_simple("^[^\\s@]+@[^\\s:]+:.*[#$]\\s*$", line, 0, 0)
					|| line.has_suffix("$") || line.has_suffix("#") || line.has_suffix("%")) {
					return;
				}
				this.session_log.puts("# " + line + "\n");
				this.session_log.flush();
			});
		}

		/**
		 * Tab / title label: host name, plus prompt, OSC title, or cwd when known.
		 *
		 * @return Display string
		 */
		public string label()
		{
			var detail = this.detail();
			if (detail.length == 0) {
				return this.connection.name;
			}
			return this.connection.name + "  " + detail;
		}

		/**
		 * Dynamic part of {@link label} (prompt preferred — OSC is often absent over SSH).
		 *
		 * @return Detail string or empty
		 */
		private string detail()
		{
			if (this.prompt_hint.length > 0) {
				return this.prompt_hint;
			}
			if (this.window_title.length > 0) {
				return this.window_title;
			}
			return this.cwd;
		}

		/**
		 * Spawn ``ssh`` for this connection; password / passphrase fed on prompt.
		 */
		public void spawn()
		{
			string[] argv = {};
			argv += "ssh";
			argv += "-p";
			argv += this.connection.port.to_string();
			foreach (var fwd in this.connection.forwards) {
				argv += "-L";
				argv += fwd.local_host + ":" + fwd.local_port.to_string()
					+ ":" + fwd.remote_host + ":" + fwd.remote_port.to_string();
			}
			if ((this.connection.auth == "publickey" || this.connection.auth == "ssh_key")
					&& this.connection.public_key.length > 0) {
				argv += "-i";
				argv += this.connection.public_key;
			}
			foreach (var opt in this.connection.options.strip().split_set(" \t")) {
				if (opt.length == 0) {
					continue;
				}
				argv += opt;
			}
			argv += this.connection.user + "@" + this.connection.host;
			var target = this.connection.user + "@" + this.connection.host + ":" + this.connection.port.to_string();
			var banner = "Connecting to " + target + " …\r\n";
			this.terminal.feed(banner.data);

			var log_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "asbru", "session_logs"
			);
			GLib.DirUtils.create_with_parents(log_dir, 0755);
			var stamp = new GLib.DateTime.now_local().format("%Y%m%d_%H%M%S");
			var log_path = GLib.Path.build_filename(
				log_dir, this.connection.uuid + "_" + this.connection.name + "_" + stamp + ".txt"
			);
			this.session_log = GLib.FileStream.open(log_path, "w");
			if (this.session_log != null) {
				this.session_log.printf("# RooTerm %s %s started %s\n", this.connection.name, target, stamp);
				this.session_log.flush();
				GLib.debug("session log path=%s", log_path);
			} else {
				GLib.warning("session log open failed path=%s", log_path);
			}

			GLib.debug("ssh spawn name=%s target=%s", this.connection.name, target);
			this.terminal.spawn_async(
				Vte.PtyFlags.DEFAULT,
				null,
				argv,
				null,
				GLib.SpawnFlags.SEARCH_PATH,
				null,
				-1,
				null,
				(term, pid, error) => {
					if (error != null) {
						GLib.warning("ssh spawn failed: %s", error.message);
						var fail = "spawn failed: " + error.message + "\r\n";
						this.terminal.feed(fail.data);
						return;
					}
					GLib.debug("ssh pid=%d name=%s", pid, this.connection.name);
				}
			);
		}
	}
}
