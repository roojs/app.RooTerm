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
		private bool sent_secret = false;
		private GLib.FileStream? session_log = null;
		private string log_seen = "";
		private bool hide_input = false;
		private bool want_output_line = false;

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
					this.want_output_line = true;
					return;
				}
				this.session_log.puts(text);
				this.session_log.flush();
				if (text.index_of_char('\n') >= 0 || text.index_of_char('\r') >= 0) {
					this.want_output_line = true;
				}
			});
			this.terminal.contents_changed.connect(() => {
				var text = this.terminal.get_text_format(Vte.Format.TEXT);
				if (text == null || text.length == 0) {
					return;
				}
				var start = 0;
				if (text.length > 400) {
					start = text.length - 400;
				}
				var tail = text.substring(start);
				if (GLib.Regex.match_simple(
					"(password|passphrase|\\[sudo\\]\\s*password).*:\\s*$",
					tail,
					GLib.RegexCompileFlags.CASELESS | GLib.RegexCompileFlags.MULTILINE,
					0
				)) {
					this.hide_input = true;
					if (!this.sent_secret) {
						if (GLib.Regex.match_simple("passphrase.*:\\s*$", tail, GLib.RegexCompileFlags.CASELESS | GLib.RegexCompileFlags.MULTILINE, 0)
							&& this.connection.passphrase.length > 0) {
							this.sent_secret = true;
							this.hide_input = false;
							var passphrase = this.connection.passphrase + "\n";
							this.terminal.feed_child(passphrase.data);
							GLib.debug("fed passphrase name=%s", this.connection.name);
						} else if (GLib.Regex.match_simple("password:\\s*$", tail, GLib.RegexCompileFlags.CASELESS | GLib.RegexCompileFlags.MULTILINE, 0)
							&& this.connection.pass.length > 0) {
							this.sent_secret = true;
							this.hide_input = false;
							var password = this.connection.pass + "\n";
							this.terminal.feed_child(password.data);
							GLib.debug("fed password name=%s", this.connection.name);
						}
					}
				}
				if (this.session_log == null) {
					this.log_seen = text;
					return;
				}
				if (text.length < this.log_seen.length) {
					this.log_seen = text;
					return;
				}
				if (text.length == this.log_seen.length) {
					return;
				}
				var delta = text.substring(this.log_seen.length);
				this.log_seen = text;
				if (!this.want_output_line || this.hide_input) {
					return;
				}
				if (delta.length > 500 || delta.index_of("\x1b") >= 0) {
					this.want_output_line = false;
					return;
				}
				var line = delta.replace("\r", "").strip();
				var nl = line.index_of_char('\n');
				if (nl >= 0) {
					line = line.substring(0, nl).strip();
				}
				this.want_output_line = false;
				if (line.length == 0) {
					return;
				}
				this.session_log.puts("# " + line + "\n");
				this.session_log.flush();
			});
		}

		/**
		 * Tab / title label: host name, plus cwd or shell window title when known.
		 *
		 * @return Display string
		 */
		public string label()
		{
			if (this.cwd.length > 0) {
				return this.connection.name + "  " + this.cwd;
			}
			if (this.window_title.length > 0) {
				return this.connection.name + "  " + this.window_title;
			}
			return this.connection.name;
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
			if (this.connection.auth_type == "publickey" && this.connection.public_key.length > 0) {
				argv += "-i";
				argv += this.connection.public_key;
			}
			foreach (var opt in this.connection.options.strip().split_set(" \t")) {
				if (opt.length == 0) {
					continue;
				}
				argv += opt;
			}
			argv += this.connection.user + "@" + this.connection.ip;
			var target = this.connection.user + "@" + this.connection.ip + ":" + this.connection.port.to_string();
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
					var text = this.terminal.get_text_format(Vte.Format.TEXT);
					this.log_seen = text != null ? text : "";
				}
			);
		}
	}
}
