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
	 * Plain SSH login. Subclasses call {@link login} then add steps.
	 */
	public class SshLogin : Job
	{
		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 */
		public SshLogin(MainWindow window, Connection connection)
		{
			base(window, connection);
		}

		/**
		 * {@link login}, then {@link State.DONE}.
		 */
		public override async void run() throws JobError
		{
			this.terminal.spawn();
			yield this.login();
			this.current_state = State.DONE;
		}

		/**
		 * Password prompt → feed password → shell prompt.
		 *
		 * Does not set {@link State.DONE} — subclasses finish after this.
		 * {@link OpenSession} overrides for password-or-shell / passphrase.
		 */
		protected virtual async void login() throws JobError
		{
			yield this.expect(State.WAIT_SSH_PASSWORD, 30000);
			this.terminal.terminal.feed_child((this.connection.pass + "\n").data);
			yield this.expect(State.WAIT_SHELL_PROMPT, 30000);
		}

		/**
		 * SSH password / passphrase and user shell prompt; then {@link Job.on_content}.
		 *
		 * @param cursor_line Non-empty cursor row text
		 */
		protected override void on_content(string cursor_line)
		{
			// ssh password / passphrase (not [sudo])
			if (GLib.Regex.match_simple(
					"(password|passphrase).*:\\s*$",
					cursor_line, GLib.RegexCompileFlags.CASELESS, 0)
					&& !GLib.Regex.match_simple(
						"\\[sudo\\].*password.*:\\s*$",
						cursor_line, GLib.RegexCompileFlags.CASELESS, 0)) {
				if (this.current_state != State.WAIT_SSH_PASSWORD) {
					GLib.debug("job current_state name=%s %d -> %d want=%d",
						this.connection.name, (int) this.current_state,
						(int) State.WAIT_SSH_PASSWORD, (int) this.want);
					this.current_state = State.WAIT_SSH_PASSWORD;
				}
				return;
			}
			// user@host:…$|# shell prompt
			if (!GLib.Regex.match_simple("^[^\\s@]+@[^\\s:]+:.*[#$]\\s*$", cursor_line, 0, 0)
					// sql / db client prompt (mysql>, postgres>, …)
					&& !GLib.Regex.match_simple(
						"^(MariaDB|mysql|sqlite3?|postgres|plsql)\\b.*>\\s*$",
						cursor_line, GLib.RegexCompileFlags.CASELESS, 0)
					// short line ending in $ / # / % (generic prompt)
					&& !((cursor_line.has_suffix("$") || cursor_line.has_suffix("#")
						|| cursor_line.has_suffix("%")) && cursor_line.length < 160)) {
				base.on_content(cursor_line);
				return;
			}
			if (this.current_state != State.WAIT_SHELL_PROMPT) {
				GLib.debug("job current_state name=%s %d -> %d want=%d",
					this.connection.name, (int) this.current_state,
					(int) State.WAIT_SHELL_PROMPT, (int) this.want);
				this.current_state = State.WAIT_SHELL_PROMPT;
			}
		}
	}
}
