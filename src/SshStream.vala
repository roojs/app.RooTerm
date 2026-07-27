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
	 * == Example ==
	 *
	 * {{{
	 * var stream = new SshStream(term.terminal, conn);
	 * stream.label_changed.connect(() => { ... });
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
		 * Emitted when {@link prompt_hint} changes.
		 */
		public signal void label_changed();

		/**
		 * Attach to ``terminal`` and connect ``on_*`` stream handlers.
		 *
		 * @param terminal VTE widget to watch
		 * @param connection Host credentials / auth
		 */
		public SshStream(Vte.Terminal terminal, Connection connection)
		{
			this.terminal = terminal;
			this.connection = connection;
			this.terminal.commit.connect(this.on_commit);
			this.terminal.contents_changed.connect(this.on_prompt);
			this.terminal.contents_changed.connect(this.on_password);
			this.terminal.contents_changed.connect(this.on_log);
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
				if (!is_prompt || last == this.prompt_hint) {
					return false;
				}
				this.prompt_hint = last;
				this.label_changed();
				return false;
			});
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
			if (!GLib.Regex.match_simple("(password|passphrase|\\[sudo\\]\\s*password).*:\\s*$", line, GLib.RegexCompileFlags.CASELESS, 0)) {
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
				this.terminal.feed_child((this.connection.passphrase + "\n").data);
				GLib.debug("fed passphrase name=%s", this.connection.name);
				return;
			}
			if (!GLib.Regex.match_simple("password:\\s*$", line, GLib.RegexCompileFlags.CASELESS, 0)
				|| this.connection.auth == "manual"
				|| this.connection.auth == "ssh_key"
				|| this.connection.auth == "publickey") {
				return;
			}
			if (this.connection.pass.length == 0) {
				try {
					var pass = Secret.password_lookup_sync(
						new Secret.Schema("org.roojs.rooterm.Connection", Secret.SchemaFlags.NONE, "uuid", Secret.SchemaAttributeType.STRING),
						null, "uuid", this.connection.uuid
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
			this.terminal.feed_child((this.connection.pass + "\n").data);
			GLib.debug("fed password name=%s", this.connection.name);
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
