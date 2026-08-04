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
	 * Plain SSH login. Subclasses call {@link login} then add steps.
	 */
	public class SshLogin : Job
	{
		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 * @param existing Adopt this tab instead of creating one
		 */
		public SshLogin(RooTerm.MainWindow window, Host.Connection connection, Terminal.Base? existing = null)
		{
			base(window, connection, existing);
		}

		/**
		 * {@link login}, then {@link State.DONE}.
		 */
		public override async void run() throws Error
		{
			this.terminal.spawn();
			yield this.login();
			this.current_state = State.DONE;
		}

		/**
		 * Password prompt → feed password → shell prompt.
		 *
		 * Host-key / 2FA / already-at-shell are caller decisions on ``expect`` false.
		 * Does not set {@link State.DONE} — subclasses finish after this.
		 * {@link OpenSession} overrides for passphrase.
		 */
		protected virtual async void login() throws Error
		{
			if (this.connection.auth == "manual") {
				while (!yield this.expect(State.WAIT_SHELL_PROMPT, 30000)) {
					switch (this.current_state) {
						case State.WAIT_HOST_CONFIRM:
						case State.WAIT_VERIFICATION_CODE:
						case State.WAIT_SSH_PASSWORD:
							continue;
						default:
							throw new Error.TIMEOUT("login shell timeout name=%s".printf(
								this.connection.name));
					}
				}
				return;
			}
			while (!yield this.expect(State.WAIT_SSH_PASSWORD, 30000)) {
				switch (this.current_state) {
					case State.WAIT_SHELL_PROMPT:
						return;
					case State.WAIT_HOST_CONFIRM:
					case State.WAIT_VERIFICATION_CODE:
						continue;
					default:
						throw new Error.TIMEOUT("login password timeout name=%s".printf(
							this.connection.name));
				}
			}
			this.terminal.terminal.feed_child((this.connection.pass + "\n").data);
			GLib.debug("login feed password name=%s pass_len=%d auth=%s",
				this.connection.name, this.connection.pass.length, this.connection.auth);
			this.current_state = State.UNKNOWN;
			while (!yield this.expect(State.WAIT_SHELL_PROMPT, 30000)) {
				switch (this.current_state) {
					case State.WAIT_VERIFICATION_CODE:
						continue;
					default:
						throw new Error.TIMEOUT("login shell timeout name=%s".printf(
							this.connection.name));
				}
			}
		}

		/**
		 * Host-key confirm, 2FA, SSH password / passphrase, and user shell prompt;
		 * then {@link Job.on_content}.
		 *
		 * @param cursor_line Non-empty cursor row text
		 */
		protected override void on_content(string cursor_line)
		{
			// SSH host-key fingerprint — user types yes/no in the VTE
			if (GLib.Regex.match_simple(
					"continue connecting|\\(yes/no",
					cursor_line, GLib.RegexCompileFlags.CASELESS, 0)) {
				if (this.current_state != State.WAIT_HOST_CONFIRM) {
					GLib.debug("job current_state name=%s %d -> %d want=%d",
						this.connection.name, (int) this.current_state,
						(int) State.WAIT_HOST_CONFIRM, (int) this.want);
					this.current_state = State.WAIT_HOST_CONFIRM;
					this.window.present();
					this.terminal.terminal.grab_focus();
				}
				return;
			}
			// 2FA / TOTP — user types the code
			if (GLib.Regex.match_simple(
					"verification code:\\s*$",
					cursor_line, GLib.RegexCompileFlags.CASELESS, 0)) {
				if (this.current_state != State.WAIT_VERIFICATION_CODE) {
					GLib.debug("job current_state name=%s %d -> %d want=%d",
						this.connection.name, (int) this.current_state,
						(int) State.WAIT_VERIFICATION_CODE, (int) this.want);
					this.current_state = State.WAIT_VERIFICATION_CODE;
					this.window.present();
					this.terminal.terminal.grab_focus();
				}
				return;
			}
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
