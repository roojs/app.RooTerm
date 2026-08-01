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

namespace RooTerm.Jobs
{
	/**
	 * Fetch LXC hosts: login + sudo → ``lxc-ls`` → parse into {@link container_names}.
	 */
	public class FetchHosts : SudoLogin
	{
		/**
		 * Parsed ``lxc-ls`` names (Dialog.Connection stages / applies them).
		 */
		public string[] container_names = {};

		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 */
		public FetchHosts(MainWindow window, Host.Connection connection)
		{
			base(window, connection);
		}

		/**
		 * {@link SshLogin.login}, {@link SudoLogin.sudo}, ``lxc-ls``, parse names,
		 * {@link State.CONTAINERS_FOUND} → {@link State.DONE}.
		 */
		public override async void run() throws Error
		{
			this.terminal.spawn();
			yield this.login();
			yield this.sudo();
			this.current_state = State.UNKNOWN;
			this.terminal.terminal.feed_child("lxc-ls -f -F name,state\n".data);
			if (!yield this.expect(State.WAIT_ROOT_PROMPT, 60000)) {
				throw new Error.TIMEOUT("fetch hosts timeout name=%s".printf(
					this.connection.name));
			}
			long end_col, end_row;
			this.terminal.terminal.get_cursor_position(out end_col, out end_row);
			size_t full_len;
			var full = this.terminal.terminal.get_text_range_format(
				Vte.Format.TEXT, 0, 0, end_row, end_col, out full_len
			);
			string[] names = {};
			if (full != null) {
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
			}
			this.container_names = names;
			GLib.debug("job fetch hosts name=%s count=%d",
				this.connection.name, names.length);
			this.current_state = State.CONTAINERS_FOUND;
			this.current_state = State.DONE;
		}
	}
}
