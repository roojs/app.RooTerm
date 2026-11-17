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
	 * Batch SSH open for one planning target.
	 *
	 * Same login as {@link OpenSession}, including sudo when set.
	 * Stops at the shell. Does not run ``lxc-console`` or
	 * ``lxc-attach``. The caller already built the terminal.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var job = new Jobs.Batch(window, connection, term);
	 * job.run.begin();
	 * }}}
	 */
	public class Batch : OpenSession
	{
		/**
		 * @param window Main window (secrets and login prompts)
		 * @param connection Host or container being opened
		 * @param existing Terminal already shown in the batch window
		 */
		public Batch(RooTerm.MainWindow window, Host.Connection connection, Terminal.Base existing)
		{
			base(window, connection, existing);
		}

		/**
		 * Password / passphrase prompt, or already at a shell.
		 */
		protected override async void login() throws Error
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
			if (this.connection.passphrase.length > 0) {
				this.terminal.terminal.feed_child((this.connection.passphrase + "\n").data);
			}
			if (this.connection.passphrase.length == 0) {
				this.terminal.terminal.feed_child((this.connection.pass + "\n").data);
			}
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
		 * Spawn, log in, and sudo when that host asks for it.
		 */
		public override async void run() throws Error
		{
			this.terminal.spawn();
			yield this.login();
			if (this.connection.sudo_after_login) {
				yield this.sudo();
			}
			this.current_state = State.DONE;
		}
	}
}
