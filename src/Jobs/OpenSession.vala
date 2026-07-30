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
	 * Open-ended SSH session: login (password, passphrase, or already at shell),
	 * optional sudo / ``lxc-console``; tab stays open when the job is disposed.
	 *
	 * Sets {@link Terminal.close_after} to ``-1`` (30s countdown if SSH exits).
	 * Host-key focus lives in {@link SshLogin.on_content}; shell focus is here after login.
	 */
	public class OpenSession : SudoLogin
	{
		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 */
		public OpenSession(MainWindow window, Connection connection)
		{
			base(window, connection);
			this.terminal.close_after = -1;
		}

		/**
		 * Password / passphrase prompt, or already at a shell — then shell.
		 * Same ``expect`` false handling as {@link SshLogin.login}; feeds passphrase when set.
		 */
		protected override async void login() throws JobError
		{
			while (!yield this.expect(State.WAIT_SSH_PASSWORD, 30000)) {
				switch (this.current_state) {
					case State.WAIT_SHELL_PROMPT:
						this.window.present();
						this.terminal.terminal.grab_focus();
						return;
					case State.WAIT_HOST_CONFIRM:
					case State.WAIT_VERIFICATION_CODE:
						continue;
					default:
						throw new JobError.TIMEOUT("login password timeout name=%s".printf(
							this.connection.name));
				}
			}
			if (this.connection.passphrase.length > 0) {
				GLib.debug("login feed passphrase name=%s phrase_len=%d",
					this.connection.name, this.connection.passphrase.length);
				this.terminal.terminal.feed_child((this.connection.passphrase + "\n").data);
			} else {
				GLib.debug("login feed password name=%s pass_len=%d auth=%s",
					this.connection.name, this.connection.pass.length, this.connection.auth);
				this.terminal.terminal.feed_child((this.connection.pass + "\n").data);
			}
			this.current_state = State.UNKNOWN;
			while (!yield this.expect(State.WAIT_SHELL_PROMPT, 30000)) {
				switch (this.current_state) {
					case State.WAIT_VERIFICATION_CODE:
						continue;
					default:
						throw new JobError.TIMEOUT("login shell timeout name=%s".printf(
							this.connection.name));
				}
			}
			this.window.present();
			this.terminal.terminal.grab_focus();
		}

		/**
		 * Spawn → {@link login} → optional {@link SudoLogin.sudo} → optional ``lxc-console`` → DONE.
		 */
		public override async void run() throws JobError
		{
			this.terminal.spawn();
			yield this.login();
			if (this.connection.sudo_after_login) {
				yield this.sudo();
			}
			if (this.connection.lxc_name.length > 0) {
				this.current_state = State.UNKNOWN;
				this.terminal.terminal.feed_child(
					("lxc-console -n " + this.connection.lxc_name + "\n").data
				);
				if (!yield this.expect(State.WAIT_SHELL_PROMPT, 30000)) {
					throw new JobError.TIMEOUT("lxc console timeout name=%s".printf(
						this.connection.name));
				}
			}
			this.current_state = State.DONE;
			this.window.present();
			this.terminal.terminal.grab_focus();
		}
	}
}
