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
	 * Remove-old-key: user shell → strip line from ``authorized_keys``.
	 *
	 * Edits ``$HOME/.ssh/authorized_keys`` for the SSH user — no sudo.
	 * Set {@link remove_pub_line} before {@link run}.
	 */
	public class RetireKey : SshLogin
	{
		/**
		 * Public-key line to remove from ``authorized_keys``.
		 */
		public string remove_pub_line = "";

		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 */
		public RetireKey(RooTerm.MainWindow window, Host.Connection connection)
		{
			base(window, connection);
		}

		/**
		 * {@link SshLogin.login}, feed retire script, confirm echo → {@link State.KEY_RETIRED}.
		 */
		public override async void run() throws Error
		{
			this.terminal.spawn();
			yield this.login();
			var line = this.remove_pub_line.strip().replace("'", "'\\''");
			this.current_state = State.UNKNOWN;
			this.terminal.terminal.feed_child(("""f="$HOME/.ssh/authorized_keys"
grep -vxF '""" + line + """' "$f" > "$f.rooterm"
mv "$f.rooterm" "$f"
chmod 600 "$f"
echo RooTerm: old key removed
""").data);
			if (!yield this.expect(State.WAIT_SHELL_PROMPT, 60000)) {
				throw new Error.TIMEOUT("retire key timeout name=%s".printf(
					this.connection.name));
			}
			long end_col, end_row;
			this.terminal.terminal.get_cursor_position(out end_col, out end_row);
			size_t full_len;
			var full = this.terminal.terminal.get_text_range_format(
				Vte.Format.TEXT, 0, 0, end_row, end_col, out full_len
			);
			if (full == null || full.index_of("RooTerm: old key removed") < 0) {
				this.current_state = State.FAILED;
				throw new Error.FAIL("retire key echo missing name=%s".printf(this.connection.name));
			}
			this.current_state = State.KEY_RETIRED;
			this.current_state = State.DONE;
		}
	}
}
