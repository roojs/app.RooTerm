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
	 * {@link Job.keep_open} — {@link dispose} unwires but does not close the tab.
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
			this.keep_open = true;
		}

		/**
		 * Password / passphrase prompt, or already at a shell — then shell.
		 */
		protected override async void login() throws JobError
		{
			this.want = State.WAIT_SSH_PASSWORD;
			GLib.debug("job open login name=%s current_state=%d",
				this.connection.name, (int) this.current_state);
			switch (this.current_state) {
				case State.WAIT_SHELL_PROMPT:
					return;
				case State.WAIT_SSH_PASSWORD:
					break;
				case State.CANCELLED:
					throw new JobError.CANCEL("job cancelled name=%s".printf(this.connection.name));
				case State.FAILED:
					throw new JobError.FAIL("terminal failure name=%s".printf(this.connection.name));
				case State.TIMEOUT:
					throw new JobError.TIMEOUT("login timeout name=%s".printf(this.connection.name));
				default:
					var resumed = false;
					ulong notify_state = this.notify["current_state"].connect(() => {
						if (resumed) {
							return;
						}
						switch (this.current_state) {
							case State.WAIT_SSH_PASSWORD:
							case State.WAIT_SHELL_PROMPT:
							case State.FAILED:
							case State.CANCELLED:
							case State.TIMEOUT:
								resumed = true;
								login.callback();
								break;
						}
					});
					uint timeout_id = GLib.Timeout.add(30000, () => {
						if (resumed) {
							return false;
						}
						this.current_state = State.TIMEOUT;
						return false;
					});
					yield;
					this.disconnect(notify_state);
					GLib.Source.remove(timeout_id);
					break;
			}
			switch (this.current_state) {
				case State.WAIT_SHELL_PROMPT:
					return;
				case State.WAIT_SSH_PASSWORD:
					break;
				case State.CANCELLED:
					throw new JobError.CANCEL("job cancelled name=%s".printf(this.connection.name));
				case State.FAILED:
					throw new JobError.FAIL("terminal failure name=%s".printf(this.connection.name));
				case State.TIMEOUT:
					throw new JobError.TIMEOUT("login timeout name=%s".printf(this.connection.name));
				default:
					throw new JobError.FAIL("login unexpected state=%d name=%s".printf(
						(int) this.current_state, this.connection.name));
			}
			if (this.connection.passphrase.length > 0) {
				this.terminal.terminal.feed_child((this.connection.passphrase + "\n").data);
			} else {
				this.terminal.terminal.feed_child((this.connection.pass + "\n").data);
			}
			yield this.expect(State.WAIT_SHELL_PROMPT, 30000);
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
				yield this.expect(State.WAIT_SHELL_PROMPT, 30000);
			}
			this.current_state = State.DONE;
		}
	}
}
