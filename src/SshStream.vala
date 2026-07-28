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
	 * VTE ``commit`` / ``contents_changed`` handlers for one {@link SshTerminal}.
	 *
	 * Construct with both ``terminal`` and ``connection`` to wire handlers.
	 * Construct with neither for a null stream (flags bag for {@link SessionController.open}).
	 *
	 * == Example ==
	 *
	 * {{{
	 * var stream = new SshStream(term.terminal, conn);
	 * stream.label_changed.connect(() => { ... });
	 * var opts = new SshStream();
	 * opts.install_key = true;
	 * }}}
	 */
	public class SshStream : Object
	{
		public Vte.Terminal terminal;
		public Connection connection;
		/**
		 * Last shell/mysql-style prompt line scraped from the screen.
		 */
		public string prompt_hint = "";
		public uint prompt_timeout = 0;
		public bool sent_secret = false;
		public GLib.FileStream? session_log = null;
		public bool hide_input = false;
		/**
		 * Absolute VTE row to read for the next ``#`` log line (``-1`` = not waiting).
		 */
		public long log_line = -1;
		/**
		 * ``sudo -i`` has been fed (wait for the next prompt before LXC steps).
		 */
		public bool sudo_sent = false;
		/**
		 * Ready for post-sudo steps (no sudo needed, or a prompt arrived after {@link sudo_sent}).
		 */
		public bool sudo_done = false;
		/**
		 * Sudo password was fed; another sudo prompt means failure.
		 */
		public bool sudo_password_fed = false;
		/**
		 * After a short arm delay, a repeated sudo password prompt emits {@link sudo_password_failed}.
		 */
		public bool sudo_fail_armed = false;
		/**
		 * ``lxc-ls`` has been fed (refresh containers).
		 */
		public bool list_sent = false;
		/**
		 * ``lxc-ls`` output has been parsed.
		 */
		public bool list_parsed = false;
		/**
		 * ``lxc-console`` has been fed.
		 */
		public bool lxc_sent = false;
		/**
		 * When true, spawn is ``ssh-copy-id``; watch output for success.
		 */
		public bool install_key = false;
		/**
		 * When true, after login remove {@link remove_pub_line} from ``authorized_keys``.
		 */
		public bool remove_old_key = false;
		/**
		 * Full line from the old ``.pub`` file to delete on the server.
		 */
		public string remove_pub_line = "";
		/**
		 * Remote remove command has been fed.
		 */
		public bool remove_sent = false;
		/**
		 * When true, after login feed ``lxc-ls`` and emit {@link containers_found}.
		 */
		public bool list_containers = false;
		/**
		 * Private key path used for {@link install_key} (no ``.pub`` suffix).
		 */
		public string install_identity = "";

		/**
		 * Emitted when {@link prompt_hint} changes.
		 */
		public signal void label_changed();

		/**
		 * Emitted when ``ssh-copy-id`` appears to have installed a key.
		 *
		 * @param identity Private key path to store on the connection
		 */
		public signal void key_installed(string identity);

		/**
		 * Emitted when ``sudo -i`` rejects the password (prompt returns).
		 */
		public signal void sudo_password_failed();

		/**
		 * Emitted after the old pubkey line was removed from ``authorized_keys``.
		 */
		public signal void old_key_removed();

		/**
		 * Emitted after ``lxc-ls`` output is parsed (refresh containers).
		 *
		 * @param names Container names from ``lxc-ls``
		 */
		public signal void containers_found(string[] names);

		/**
		 * Wire ``on_*`` handlers when both arguments are set; otherwise a null stream.
		 *
		 * @param terminal VTE to watch, or null for a null stream
		 * @param connection Host credentials / auth, or null for a null stream
		 */
		public SshStream(Vte.Terminal? terminal = null, Connection? connection = null)
		{
			if (terminal == null || connection == null) {
				return;
			}
			this.terminal = terminal;
			this.connection = connection;
			this.terminal.commit.connect(this.on_commit);
			this.terminal.contents_changed.connect(this.on_prompt);
			this.terminal.contents_changed.connect(this.on_password);
			this.terminal.contents_changed.connect(this.on_sudo_fail);
			this.terminal.contents_changed.connect(this.on_log);
			this.terminal.contents_changed.connect(this.on_key);
			this.label_changed.connect(() => {
				if (this.install_key) {
					return;
				}
				if (!this.connection.sudo_after_login) {
					this.sudo_done = true;
					return;
				}
				if (this.sudo_sent) {
					this.sudo_done = true;
					this.sudo_fail_armed = false;
					return;
				}
				this.sudo_sent = true;
				this.sudo_password_fed = false;
				this.sudo_fail_armed = false;
				this.sent_secret = false;
				GLib.debug("sudo -i name=%s auth=%s pass_len=%d",
					this.connection.name, this.connection.auth, this.connection.pass.length);
				this.terminal.feed_child("sudo -i\n".data);
			});
			this.label_changed.connect(this.on_lxc_ls);
			this.label_changed.connect(() => {
				if (this.install_key || this.list_containers || this.lxc_sent) {
					return;
				}
				if (!this.sudo_done || this.connection.lxc_name.length == 0) {
					return;
				}
				this.lxc_sent = true;
				this.terminal.feed_child(
					("lxc-console -n " + this.connection.lxc_name + "\n").data
				);
			});
			this.label_changed.connect(() => {
				if (!this.remove_old_key || this.remove_sent || this.install_key) {
					return;
				}
				if (!this.sudo_done) {
					return;
				}
				if (this.remove_pub_line.strip().length == 0) {
					return;
				}
				this.remove_sent = true;
				var line = this.remove_pub_line.strip().replace("'", "'\\''");
				var cmd = """f="$HOME/.ssh/authorized_keys"
grep -vxF '""" + line + """' "$f" > "$f.rooterm"
mv "$f.rooterm" "$f"
chmod 600 "$f"
echo RooTerm: old key removed
""";
				GLib.debug("remove old key name=%s", this.connection.name);
				this.terminal.feed_child(cmd.data);
			});
			this.terminal.contents_changed.connect(this.on_remove_old);
		}

		/**
		 * Log typed input; redact when hiding a password line.
		 *
		 * @param text Committed keystrokes
		 * @param size Byte length from VTE
		 */
		private void on_commit(string text, uint size)
		{
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
				long col, row;
				this.terminal.get_cursor_position(out col, out row);
				this.log_line = row + 1;
				return;
			}
			this.session_log.puts(text);
			this.session_log.flush();
			if (text.index_of_char('\n') < 0 && text.index_of_char('\r') < 0) {
				return;
			}
			long col, row;
			this.terminal.get_cursor_position(out col, out row);
			this.log_line = row + 1;
		}

		/**
		 * Debounced scrape of the cursor row for a shell/sql prompt.
		 */
		private void on_prompt()
		{
			if (this.prompt_timeout != 0) {
				return;
			}
			this.prompt_timeout = GLib.Timeout.add(120, () => {
				this.prompt_timeout = 0;
				long col, row;
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
				if (!is_prompt) {
					return false;
				}
				var waiting_lxc = this.list_containers && this.list_sent && !this.list_parsed;
				if (last == this.prompt_hint && !waiting_lxc) {
					return false;
				}
				this.prompt_hint = last;
				this.label_changed();
				return false;
			});
		}

		/**
		 * Feed ``lxc-ls -f -F name,state`` after sudo; on the next prompt parse rows.
		 */
		private void on_lxc_ls()
		{
			if (this.install_key || !this.list_containers) {
				return;
			}
			if (!this.sudo_done) {
				return;
			}
			if (!this.list_sent) {
				this.list_sent = true;
				GLib.debug("lxc-ls feed name=%s", this.connection.name);
				this.terminal.feed_child("lxc-ls -f -F name,state\n".data);
				return;
			}
			if (this.list_parsed) {
				return;
			}
			this.list_parsed = true;
			long end_col, end_row;
			this.terminal.get_cursor_position(out end_col, out end_row);
			size_t full_len;
			var full = this.terminal.get_text_range_format(
				Vte.Format.TEXT, 0, 0, end_row, end_col, out full_len
			);
			string[] names = {};
			if (full == null) {
				GLib.debug("lxc-ls empty buffer name=%s", this.connection.name);
				this.containers_found(names);
				return;
			}
			var after = full;
			var cmd_at = full.last_index_of("lxc-ls");
			if (cmd_at >= 0) {
				after = full.substring(cmd_at);
			}
			var saw_header = false;
			foreach (var part in after.split("\n")) {
				var line = part.replace("\r", "").strip();
				if (line.length == 0) {
					continue;
				}
				var cols = line.split_set(" \t", 0);
				string[] fields = {};
				foreach (var col in cols) {
					if (col.length == 0) {
						continue;
					}
					fields += col;
				}
				if (fields.length < 2) {
					continue;
				}
				if (fields[0] == "NAME") {
					saw_header = true;
					continue;
				}
				if (!saw_header) {
					continue;
				}
				if (!GLib.Regex.match_simple(
						"^(RUNNING|STOPPED|FROZEN|STARTING|ABORTING|STOPPING)$",
						fields[1], 0, 0)) {
					continue;
				}
				if (!GLib.Regex.match_simple(
						"^[A-Za-z0-9][A-Za-z0-9_.-]*$", fields[0], 0, 0)) {
					continue;
				}
				names += fields[0];
			}
			GLib.debug("lxc-ls parsed name=%s header=%d count=%d",
				this.connection.name, (int) saw_header, names.length);
			this.containers_found(names);
		}

		/**
		 * After a sudo password was fed, ``Sorry, try again`` means it failed.
		 */
		private void on_sudo_fail()
		{
			if (!this.sudo_password_fed || this.sudo_done) {
				return;
			}
			long col, row;
			this.terminal.get_cursor_position(out col, out row);
			size_t len;
			var start = row > 6 ? row - 6 : 0;
			var raw = this.terminal.get_text_range_format(
				Vte.Format.TEXT, start, 0, row, col, out len
			);
			if (raw == null) {
				return;
			}
			if (raw.index_of("Sorry, try again") < 0
					&& raw.index_of("incorrect password attempt") < 0) {
				return;
			}
			this.sudo_fail_armed = false;
			this.sudo_password_fed = false;
			GLib.debug("sudo password failed (sorry) name=%s", this.connection.name);
			this.sudo_password_failed();
		}

		/**
		 * Detect password/passphrase prompts and feed from connection / libsecret.
		 */
		private void on_password()
		{
			if (this.hide_input) {
				return;
			}
			long col, row;
			this.terminal.get_cursor_position(out col, out row);
			size_t len;
			var raw = this.terminal.get_text_range_format(Vte.Format.TEXT, row, 0, row, col, out len);
			var line = raw != null ? raw.replace("\r", "").strip() : "";
			if (line.length == 0) {
				return;
			}
			if (!GLib.Regex.match_simple(
					"(password|passphrase|\\[sudo\\].*password).*:\\s*$",
					line, GLib.RegexCompileFlags.CASELESS, 0)) {
				return;
			}
			var is_sudo = GLib.Regex.match_simple(
				"\\[sudo\\].*password.*:\\s*$", line, GLib.RegexCompileFlags.CASELESS, 0
			);
			GLib.debug("password line=%s sudo=%d sent=%d auth=%s pass_len=%d name=%s",
				line, (int) is_sudo, (int) this.sent_secret, this.connection.auth,
				this.connection.pass.length, this.connection.name);
			if (is_sudo && this.sudo_password_fed && !this.sudo_done) {
				if (this.sudo_fail_armed) {
					this.sudo_fail_armed = false;
					this.sudo_password_fed = false;
					GLib.debug("sudo password failed name=%s", this.connection.name);
					this.sudo_password_failed();
				}
				return;
			}
			if (this.sent_secret) {
				return;
			}
			if (GLib.Regex.match_simple("passphrase.*:\\s*$", line, GLib.RegexCompileFlags.CASELESS, 0)
				&& this.connection.passphrase.length > 0
				&& this.connection.auth != "manual") {
				this.sent_secret = true;
				this.terminal.feed_child((this.connection.passphrase + "\n").data);
				GLib.debug("fed passphrase name=%s", this.connection.name);
				return;
			}
			if (!GLib.Regex.match_simple("password.*:\\s*$", line, GLib.RegexCompileFlags.CASELESS, 0)
					&& !is_sudo) {
				GLib.debug("password skip no match name=%s", this.connection.name);
				return;
			}
			if (this.connection.auth == "manual") {
				GLib.debug("password skip manual name=%s", this.connection.name);
				return;
			}
			if (!is_sudo
					&& (this.connection.auth == "ssh_key" || this.connection.auth == "publickey")
					&& !this.install_key) {
				GLib.debug("password skip ssh_key name=%s", this.connection.name);
				return;
			}
			if (this.connection.pass.length == 0) {
				var secret_uuid = this.connection.uuid;
				if (this.connection.lxc_container && this.connection.parent_uuid.length > 0) {
					secret_uuid = this.connection.parent_uuid;
				}
				try {
					var pass = Secret.password_lookup_sync(
						new Secret.Schema(
							"org.roojs.rooterm.Connection", Secret.SchemaFlags.NONE,
							"uuid", Secret.SchemaAttributeType.STRING
						),
						null,
						"uuid",
						secret_uuid
					);
					this.connection.pass = pass != null ? pass : "";
				} catch (GLib.Error e) {
					GLib.warning("secret load failed uuid=%s: %s", secret_uuid, e.message);
				}
				GLib.debug("password secret uuid=%s pass_len=%d name=%s",
					secret_uuid, this.connection.pass.length, this.connection.name);
			}
			if (this.connection.pass.length == 0) {
				GLib.debug("password skip empty name=%s line=%s", this.connection.name, line);
				if (is_sudo) {
					this.terminal.feed(
						"\r\n# RooTerm: no sudo password in keyring — edit connection and save it\r\n".data
					);
					this.sudo_password_failed();
				}
				return;
			}
			this.sent_secret = true;
			this.hide_input = true;
			this.terminal.feed_child((this.connection.pass + "\n").data);
			this.hide_input = false;
			if (is_sudo) {
				this.sudo_password_fed = true;
				this.sudo_fail_armed = false;
				GLib.Timeout.add(500, () => {
					if (this.sudo_password_fed && !this.sudo_done) {
						this.sudo_fail_armed = true;
					}
					return false;
				});
			}
			GLib.debug("fed password name=%s sudo=%d", this.connection.name, (int) is_sudo);
		}

		/**
		 * Watch ``ssh-copy-id`` output for a successful key install.
		 */
		private void on_key()
		{
			if (!this.install_key || this.install_identity.length == 0) {
				return;
			}
			long col, row;
			this.terminal.get_cursor_position(out col, out row);
			size_t len;
			var raw = this.terminal.get_text_range_format(
				Vte.Format.TEXT, 0, 0, row, col, out len
			);
			if (raw == null) {
				return;
			}
			if (raw.index_of("Number of key(s) added") < 0
					&& raw.index_of("already exist") < 0) {
				return;
			}
			var identity = this.install_identity;
			this.install_key = false;
			this.key_installed(identity);
		}

		/**
		 * Watch for ``RooTerm: old key removed`` after {@link remove_old_key}.
		 */
		private void on_remove_old()
		{
			if (!this.remove_old_key || !this.remove_sent) {
				return;
			}
			long col, row;
			this.terminal.get_cursor_position(out col, out row);
			size_t len;
			var raw = this.terminal.get_text_range_format(
				Vte.Format.TEXT, 0, 0, row, col, out len
			);
			if (raw == null || raw.index_of("RooTerm: old key removed") < 0) {
				return;
			}
			this.remove_old_key = false;
			GLib.debug("old key removed name=%s", this.connection.name);
			this.old_key_removed();
		}

		/**
		 * When waiting after Enter, log the command line as ``# …``.
		 */
		private void on_log()
		{
			if (this.session_log == null || this.log_line < 0 || this.hide_input) {
				return;
			}
			long col, row;
			this.terminal.get_cursor_position(out col, out row);
			if (row < this.log_line) {
				return;
			}
			var end_col = row > this.log_line ? this.terminal.get_column_count() : col;
			if (end_col <= 0) {
				return;
			}
			size_t len;
			var raw = this.terminal.get_text_range_format(Vte.Format.TEXT, this.log_line, 0, this.log_line, end_col, out len);
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
		}
	}
}
