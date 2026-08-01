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

namespace RooTerm.Terminal
{
	/**
	 * VTE ``commit`` / ``contents_changed`` / cwd handlers for one {@link Base}.
	 *
	 * Construct with a {@link Base} to wire handlers, or with neither for a
	 * flags bag; {@link Ssh} then calls {@link attach}.
	 *
	 * Local tabs: on a prompt-looking line, ``/proc`` cwd / peer user →
	 * {@link Base.cwd}. SSH tabs: prompt scrape for labels, session log,
	 * ``ssh-copy-id`` watch. OSC 7 also lands here.
	 * Login / sudo / passphrase / ``lxc-console`` feeds live in Jobs.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var stream = new Stream(term);
	 * stream.label_changed.connect(() => { ... });
	 * }}}
	 */
	public class Stream : Object
	{
		/**
		 * Streams waiting for a quiet settle before {@link check_cwd}.
		 */
		private static GLib.GenericArray<Stream> prompt_waiters {
			get;
			set;
			default = new GLib.GenericArray<Stream>();
		}
		/**
		 * Shared 500ms cwd/prompt watcher (started once, never stopped).
		 */
		private static uint is_watching_cwd = 0;

		/**
		 * Owning tab (pid / pty / {@link Base.cwd}).
		 */
		public weak Base session;
		public Vte.Terminal terminal;
		public Host.Connection connection;
		/**
		 * Last shell/mysql-style prompt line scraped from the screen.
		 */
		public string prompt_hint = "";
		/**
		 * Monotonic time of last output while waiting for a prompt (µs).
		 */
		private int64 prompt_activity = 0;
		/**
		 * True after Enter / attach until a prompt line is scraped.
		 */
		private bool await_prompt = false;
		/**
		 * True while this stream is in {@link prompt_waiters}.
		 */
		private bool prompt_queued = false;
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
		public Stream(Base? session = null, Host.Connection? connection = null)
		{
			if (is_watching_cwd == 0) {
				is_watching_cwd = GLib.Timeout.add(500, () => {
					var now = GLib.get_monotonic_time();
					var i = 0;
					while (i < prompt_waiters.length) {
						var stream = prompt_waiters[i];
						if (now - stream.prompt_activity < 500 * 1000) {
							i++;
							continue;
						}
						stream.check_cwd();
						stream.prompt_queued = false;
						prompt_waiters.remove_index(i);
					}
					return true;
				});
			}
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
		public void attach(Base session, Host.Connection? connection = null)
		{
			if (this.terminal != null) {
				return;
			}
			this.session = session;
			this.terminal = session.terminal;
			this.connection = connection != null ? connection : session.connection;
			// Catch the first shell prompt after spawn.
			this.await_prompt = true;
			this.prompt_activity = GLib.get_monotonic_time();
			prompt_waiters.add(this);
			this.prompt_queued = true;
			this.terminal.commit.connect(this.on_commit);
			this.terminal.contents_changed.connect(() => {
				if (!this.await_prompt) {
					return;
				}
				this.prompt_activity = GLib.get_monotonic_time();
				if (!this.prompt_queued) {
					prompt_waiters.add(this);
					this.prompt_queued = true;
				}
			});
			this.terminal.contents_changed.connect(this.on_log);
			this.terminal.contents_changed.connect(this.on_key);
			this.terminal.termprop_changed.connect(this.on_termprop);
			this.terminal.child_exited.connect(() => {
				this.await_prompt = false;
				if (this.prompt_queued) {
					this.prompt_queued = false;
					prompt_waiters.remove(this);
				}
			});
		}

		/**
		 * OSC 7 → session {@link Base.cwd}.
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
		 * Log typed input; redact when hiding a password line.
		 * Enter starts a prompt watch (label / local ``/proc``).
		 *
		 * @param text Committed keystrokes
		 * @param size Byte length from VTE
		 */
		private void on_commit(string text, uint size)
		{
			var eol = text.index_of_char('\n') >= 0 || text.index_of_char('\r') >= 0;
			if (eol) {
				this.await_prompt = true;
				this.prompt_activity = GLib.get_monotonic_time();
				if (!this.prompt_queued) {
					prompt_waiters.add(this);
					this.prompt_queued = true;
				}
			}
			if (this.session_log == null) {
				return;
			}
			if (this.hide_input) {
				if (!eol) {
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
			if (!eol) {
				return;
			}
			long col, row;
			this.terminal.get_cursor_position(out col, out row);
			this.log_line = row + 1;
		}

		/**
		 * After a quiet settle: if the cursor row looks like a prompt, update
		 * cwd / peer user (local ``/proc``) or SSH prompt hint / path.
		 *
		 * Not login/auth — Jobs own password / passphrase / sudo. Ignores
		 * password lines so the label does not become ``Enter passphrase:``.
		 */
		private void check_cwd()
		{
			long col, row;
			this.terminal.get_cursor_position(out col, out row);
			size_t len;
			// Prefer full row (trailing spaces stripped) so a short cursor col still works.
			var end_col = this.terminal.get_column_count();
			if (col > end_col) {
				end_col = col;
			}
			var raw = this.terminal.get_text_range_format(Vte.Format.TEXT, row, 0, row, end_col, out len);
			var last = raw != null ? raw.replace("\r", "").strip() : "";
			// Multiline prompts: path often on the previous row, ``$``/``#`` alone here.
			if (last.length > 0 && last.length <= 2 && (last == "$" || last == "#" || last == "%") && row > 0) {
				var prev_raw = this.terminal.get_text_range_format(Vte.Format.TEXT, row - 1, 0, row - 1, end_col, out len);
				var prev = prev_raw != null ? prev_raw.replace("\r", "").strip() : "";
				if (prev.length > 0 && prev.length < 240) {
					last = prev + last;
				}
			}
			if (last.length == 0 || last.length > 240) {
				return;
			}
			// Auth prompts are not titles.
			if (GLib.Regex.match_simple("(password|passphrase).*:\\s*$", last, GLib.RegexCompileFlags.CASELESS, 0)) {
				return;
			}
			var is_prompt = GLib.Regex.match_simple("^[^\\s@]+@[^\\s:]+:.*[#$]\\s*$", last, 0, 0)
				|| GLib.Regex.match_simple("^(MariaDB|mysql|sqlite3?|postgres|plsql)\\b.*>\\s*$", last, GLib.RegexCompileFlags.CASELESS, 0)
				|| ((last.has_suffix("$") || last.has_suffix("#") || last.has_suffix("%")) && last.length < 160);
			if (!is_prompt) {
				return;
			}
			this.await_prompt = false;
			var local = this.session as Local;
			if (local != null && this.session.child_pid > 0) {
				// ``/proc`` st_uid works for root shells; cwd often EACCES after ``sudo su``.
				var pid = this.session.child_pid;
				if (this.terminal.pty != null) {
					var fg = Posix.tcgetpgrp(this.terminal.pty.fd);
					if (fg > 0) {
						pid = (int) fg;
					}
				}
				var user = "";
				Posix.Stat st;
				if (Posix.stat("/proc/%d".printf(pid), out st) == 0) {
					unowned Posix.Passwd? pw = Posix.getpwuid(st.st_uid);
					if (pw != null) {
						user = pw.pw_name;
					}
				}
				var link = "";
				try {
					link = GLib.FileUtils.read_link("/proc/%d/cwd".printf(pid));
				} catch (GLib.FileError e) {
					GLib.debug("local cwd read failed pid=%d: %s", pid, e.message);
				}
				var cwd_changed = link.length > 0 && link != this.session.cwd;
				var user_changed = user.length > 0 && user != local.peer_user;
				if (cwd_changed || user_changed) {
					GLib.debug("local cwd pid=%d user=%s path=%s", pid, user, link.length > 0 ? link : this.session.cwd);
					if (cwd_changed) {
						this.session.cwd = link;
					}
					if (user_changed) {
						local.peer_user = user;
					}
					this.session.label_changed();
				}
			}
			if (last == this.prompt_hint) {
				return;
			}
			GLib.debug("prompt_hint name=%s hint=%s", this.connection.name, last);
			this.prompt_hint = last;
			// Local tabs use ``/proc``; prompt path is often ``~`` and would clobber it.
			if (local == null && GLib.Regex.match_simple("^[^\\s@]+@[^\\s:]+:.+[#$]\\s*$", last, 0, 0)) {
				var colon = last.index_of_char(':');
				var dir = last.substring(colon + 1);
				dir = dir.substring(0, dir.length - 1);
				if (dir.length > 0 && dir != this.session.cwd) {
					this.session.cwd = dir;
					this.session.label_changed();
				}
			}
			this.label_changed();
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
			var raw = this.terminal.get_text_range_format(Vte.Format.TEXT, 0, 0, row, col, out len);
			if (raw == null) {
				return;
			}
			if (raw.index_of("Number of key(s) added") < 0 && raw.index_of("already exist") < 0) {
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
