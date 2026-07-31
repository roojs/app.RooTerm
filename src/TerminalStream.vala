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
	 * VTE ``commit`` / ``contents_changed`` / cwd handlers for one {@link Terminal}.
	 *
	 * Construct with a {@link Terminal} to wire handlers, or with neither for a
	 * flags bag; {@link SshTerminal} then calls {@link attach}.
	 *
	 * Local tabs: ``/proc`` cwd → session {@link Terminal.cwd}. SSH tabs: prompt
	 * scrape for labels, session log, ``ssh-copy-id`` watch. OSC 7 also lands here.
	 * Login / sudo / passphrase / ``lxc-console`` feeds live in Jobs.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var stream = new TerminalStream(term);
	 * stream.label_changed.connect(() => { ... });
	 * }}}
	 */
	public class TerminalStream : Object
	{
		/**
		 * Owning tab (pid / pty / {@link Terminal.cwd}).
		 */
		public weak Terminal session;
		public Vte.Terminal terminal;
		public Connection connection;
		/**
		 * Last shell/mysql-style prompt line scraped from the screen.
		 */
		public string prompt_hint = "";
		public uint prompt_timeout = 0;
		public uint cwd_timeout = 0;
		public GLib.FileStream? session_log = null;
		public bool hide_input = false;
		/**
		 * Absolute VTE row to read for the next ``#`` log line (``-1`` = not waiting).
		 */
		public long log_line = -1;
		/**
		 * When true, spawn is ``ssh-copy-id``; watch output for success.
		 */
		public bool install_key = false;
		/**
		 * Private key path used for {@link install_key} (no ``.pub`` suffix).
		 */
		public string install_identity = "";

		/**
		 * Emitted when {@link prompt_hint} changes (SSH tab labels).
		 */
		public signal void label_changed();

		/**
		 * Emitted when ``ssh-copy-id`` appears to have installed a key.
		 *
		 * @param identity Private key path to store on the connection
		 */
		public signal void key_installed(string identity);

		/**
		 * Wire ``on_*`` when ``session`` is set; otherwise a flags bag
		 * (attach later via {@link attach}).
		 *
		 * @param session Tab to watch, or null for a flags bag
		 * @param connection Host credentials / auth (defaults to ``session.connection``)
		 */
		public TerminalStream(Terminal? session = null, Connection? connection = null)
		{
			if (session == null) {
				return;
			}
			this.attach(session, connection);
		}

		/**
		 * Bind this stream to a tab (idempotent if already attached).
		 *
		 * @param session Tab to watch
		 * @param connection Host credentials / auth (defaults to ``session.connection``)
		 */
		public void attach(Terminal session, Connection? connection = null)
		{
			if (this.terminal != null) {
				return;
			}
			this.session = session;
			this.terminal = session.terminal;
			this.connection = connection != null ? connection : session.connection;
			this.terminal.commit.connect(this.on_commit);
			this.terminal.contents_changed.connect(this.on_prompt);
			this.terminal.contents_changed.connect(this.on_log);
			this.terminal.contents_changed.connect(this.on_key);
			this.terminal.contents_changed.connect(this.on_cwd);
			this.terminal.termprop_changed.connect(this.on_termprop);
			this.terminal.child_exited.connect(() => {
				if (this.cwd_timeout != 0) {
					GLib.Source.remove(this.cwd_timeout);
					this.cwd_timeout = 0;
				}
				if (this.prompt_timeout != 0) {
					GLib.Source.remove(this.prompt_timeout);
					this.prompt_timeout = 0;
				}
			});
		}

		/**
		 * OSC 7 → session {@link Terminal.cwd}.
		 *
		 * @param prop Termprop name from VTE
		 */
		private void on_termprop(string prop)
		{
			if (prop != Vte.TERMPROP_CURRENT_DIRECTORY_URI) {
				return;
			}
			var uri = this.terminal.ref_termprop_uri(prop);
			if (uri == null) {
				return;
			}
			// Prefer Uri path: File.get_path() is null for file://hostname/...
			var path = uri.get_path();
			if (path == null || path.length == 0) {
				path = GLib.File.new_for_uri(uri.to_string()).get_path();
			}
			if (path == null || path.length == 0) {
				return;
			}
			var unesc = GLib.Uri.unescape_string(path);
			var dir = unesc != null ? unesc : path;
			if (dir.length > 0 && dir != this.session.cwd) {
				this.session.cwd = dir;
				this.session.label_changed();
			}
		}

		/**
		 * Local ``/proc`` cwd after screen activity (no-op for SSH child pids).
		 */
		private void on_cwd()
		{
			if (this.session.connection.kind != ConnectionKind.LOCAL_PATH) {
				return;
			}
			if (this.cwd_timeout != 0) {
				GLib.Source.remove(this.cwd_timeout);
			}
			this.cwd_timeout = GLib.Timeout.add(150, () => {
				this.cwd_timeout = 0;
				if (this.session.child_pid <= 0) {
					return false;
				}
				var pid = this.session.child_pid;
				if (this.terminal.pty != null) {
					var fg = Posix.tcgetpgrp(this.terminal.pty.fd);
					if (fg > 0) {
						pid = (int) fg;
					}
				}
				try {
					var link = GLib.FileUtils.read_link("/proc/%d/cwd".printf(pid));
					if (link.length == 0 || link == this.session.cwd) {
						return false;
					}
					GLib.debug("local cwd pid=%d path=%s", pid, link);
					this.session.cwd = link;
					this.session.label_changed();
				} catch (GLib.FileError e) {
					GLib.debug("local cwd read failed pid=%d: %s", pid, e.message);
				}
				return false;
			});
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
		 * Trailing-edge scrape of the cursor row for tab-label text ({@link prompt_hint}).
		 *
		 * Not login/auth — Jobs own password / passphrase / sudo. This only updates
		 * the tab title when the line looks like a shell or db prompt, and ignores
		 * password lines so the label does not briefly become ``Enter passphrase:``.
		 * Resets the timer on each change so a slow redraw still catches the final prompt.
		 */
		private void on_prompt()
		{
			if (this.prompt_timeout != 0) {
				GLib.Source.remove(this.prompt_timeout);
			}
			this.prompt_timeout = GLib.Timeout.add(120, () => {
				this.prompt_timeout = 0;
				long col, row;
				this.terminal.get_cursor_position(out col, out row);
				size_t len;
				// Prefer full row (trailing spaces stripped) so a short cursor col still works.
				var end_col = this.terminal.get_column_count();
				if (col > end_col) {
					end_col = col;
				}
				var raw = this.terminal.get_text_range_format(
					Vte.Format.TEXT, row, 0, row, end_col, out len
				);
				var last = raw != null ? raw.replace("\r", "").strip() : "";
				// Multiline prompts: path often on the previous row, ``$``/``#`` alone here.
				if (last.length > 0 && last.length <= 2
						&& (last == "$" || last == "#" || last == "%")
						&& row > 0) {
					var prev_raw = this.terminal.get_text_range_format(
						Vte.Format.TEXT, row - 1, 0, row - 1, end_col, out len
					);
					var prev = prev_raw != null ? prev_raw.replace("\r", "").strip() : "";
					if (prev.length > 0 && prev.length < 240) {
						last = prev + last;
					}
				}
				if (last.length == 0 || last.length > 240) {
					return false;
				}
				// Auth prompts are not titles.
				if (GLib.Regex.match_simple("(password|passphrase).*:\\s*$", last, GLib.RegexCompileFlags.CASELESS, 0)) {
					return false;
				}
				var is_prompt = GLib.Regex.match_simple("^[^\\s@]+@[^\\s:]+:.*[#$]\\s*$", last, 0, 0)
					|| GLib.Regex.match_simple("^(MariaDB|mysql|sqlite3?|postgres|plsql)\\b.*>\\s*$", last, GLib.RegexCompileFlags.CASELESS, 0)
					|| ((last.has_suffix("$") || last.has_suffix("#") || last.has_suffix("%")) && last.length < 160);
				if (!is_prompt) {
					return false;
				}
				if (last == this.prompt_hint) {
					return false;
				}
				GLib.debug("prompt_hint name=%s hint=%s", this.connection.name, last);
				this.prompt_hint = last;
				try {
					var re = new GLib.Regex("^[^\\s@]+@[^\\s:]+:(.+)[#$]\\s*$");
					MatchInfo info;
					if (re.match(last, 0, out info)) {
						var dir = info.fetch(1);
						if (dir != null && dir.length > 0 && dir != this.session.cwd) {
							this.session.cwd = dir;
							this.session.label_changed();
						}
					}
				} catch (GLib.RegexError e) {
					GLib.debug("prompt cwd parse: %s", e.message);
				}
				this.label_changed();
				return false;
			});
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
