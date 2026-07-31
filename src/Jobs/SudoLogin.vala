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
	 * Mock SSH + sudo: {@link SshLogin.login}, then {@link sudo} to root.
	 */
	public class SudoLogin : SshLogin
	{
		/**
		 * Sudo password was fed; another sudo prompt or ``Sorry`` → {@link State.FAILED}.
		 */
		private bool sudo_password_fed = false;

		/**
		 * After a short arm delay, a repeated sudo password prompt means failure.
		 */
		private bool sudo_fail_armed = false;

		/**
		 * Root prompt seen after sudo; stop fail checks.
		 */
		private bool sudo_done = false;

		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 */
		public SudoLogin(MainWindow window, Host.Connection connection)
		{
			base(window, connection);
		}

		/**
		 * {@link login}, {@link sudo}, then {@link State.DONE}.
		 */
		public override async void run() throws JobError
		{
			this.terminal.spawn();
			yield this.login();
			yield this.sudo();
			this.current_state = State.DONE;
		}

		/**
		 * ``sudo -i`` → sudo password → root prompt.
		 *
		 * Does not set {@link State.DONE} — subclasses finish after this.
		 */
		protected async void sudo() throws JobError
		{
			this.sudo_password_fed = false;
			this.sudo_fail_armed = false;
			this.sudo_done = false;
			this.terminal.terminal.feed_child("sudo -i\n".data);
			if (!yield this.expect(State.WAIT_SUDO_PASSWORD, 15000)) {
				throw new JobError.TIMEOUT("sudo password timeout name=%s".printf(
					this.connection.name));
			}
			this.terminal.terminal.feed_child((this.connection.pass + "\n").data);
			this.sudo_password_fed = true;
			GLib.Timeout.add(500, () => {
				if (this.sudo_password_fed && !this.sudo_done) {
					this.sudo_fail_armed = true;
				}
				return false;
			});
			if (!yield this.expect(State.WAIT_ROOT_PROMPT, 15000)) {
				throw new JobError.TIMEOUT("sudo root timeout name=%s".printf(
					this.connection.name));
			}
			this.sudo_done = true;
		}

		/**
		 * Mark sudo rejected and notify the session UI.
		 */
		private void fail_sudo()
		{
			this.sudo_fail_armed = false;
			this.sudo_password_fed = false;
			GLib.debug("sudo password failed name=%s", this.connection.name);
			this.window.sessions.sudo_password_failed(this.connection);
			if (this.current_state != State.FAILED) {
				GLib.debug("job current_state name=%s %d -> %d want=%d",
					this.connection.name, (int) this.current_state,
					(int) State.FAILED, (int) this.want);
				this.current_state = State.FAILED;
			}
		}

		/**
		 * Sudo password / fail / root ``#`` prompt; otherwise {@link SshLogin.on_content}.
		 *
		 * @param cursor_line Non-empty cursor row text
		 */
		protected override void on_content(string cursor_line)
		{
			if (this.sudo_password_fed && !this.sudo_done) {
				long col, row;
				this.terminal.terminal.get_cursor_position(out col, out row);
				size_t len;
				var start = row > 6 ? row - 6 : 0;
				var raw = this.terminal.terminal.get_text_range_format(
					Vte.Format.TEXT, start, 0, row, col, out len
				);
				if (raw != null
						&& (raw.index_of("Sorry, try again") >= 0
							|| raw.index_of("incorrect password attempt") >= 0)) {
					this.fail_sudo();
					return;
				}
			}
			// [sudo] password prompt
			if (GLib.Regex.match_simple(
					"\\[sudo\\].*password.*:\\s*$",
					cursor_line, GLib.RegexCompileFlags.CASELESS, 0)) {
				if (this.sudo_password_fed && this.sudo_fail_armed && !this.sudo_done) {
					this.fail_sudo();
					return;
				}
				if (this.current_state != State.WAIT_SUDO_PASSWORD) {
					GLib.debug("job current_state name=%s %d -> %d want=%d",
						this.connection.name, (int) this.current_state,
						(int) State.WAIT_SUDO_PASSWORD, (int) this.want);
					this.current_state = State.WAIT_SUDO_PASSWORD;
				}
				return;
			}
			// root: user@host:…# or any line ending in #
			if (GLib.Regex.match_simple("^[^\\s@]+@[^\\s:]+:.*#\\s*$", cursor_line, 0, 0)
					|| cursor_line.has_suffix("#")) {
				if (this.current_state != State.WAIT_ROOT_PROMPT) {
					GLib.debug("job current_state name=%s %d -> %d want=%d",
						this.connection.name, (int) this.current_state,
						(int) State.WAIT_ROOT_PROMPT, (int) this.want);
					this.current_state = State.WAIT_ROOT_PROMPT;
				}
				return;
			}
			base.on_content(cursor_line);
		}
	}
}
