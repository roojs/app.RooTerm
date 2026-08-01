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
	 * ``ssh-copy-id``: password → {@link State.KEY_INSTALLED}.
	 *
	 * Sets ``install_key`` on {@link Job.stream} in the ctor. {@link Dialog.Key} stays outside.
	 * May see host-key confirm (manual yes), then passphrase and/or host password.
	 */
	public class SetupKey : SshLogin
	{
		/**
		 * Identity from ``ssh-copy-id`` success (Dialog.Connection stages it).
		 */
		public string installed_identity = "";

		private ulong key_installed_id = 0;

		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 */
		public SetupKey(MainWindow window, Host.Connection connection)
		{
			base(window, connection);
			this.stream.install_key = true;
			this.key_installed_id = this.stream.key_installed.connect((identity) => {
				this.installed_identity = identity;
				if (this.current_state != State.KEY_INSTALLED) {
					GLib.debug("job current_state name=%s %d -> %d want=%d",
						this.connection.name, (int) this.current_state,
						(int) State.KEY_INSTALLED, (int) this.want);
					this.current_state = State.KEY_INSTALLED;
				}
			});
		}

		public override void dispose()
		{
			if (this.key_installed_id != 0) {
				this.stream.disconnect(this.key_installed_id);
				this.key_installed_id = 0;
			}
			base.dispose();
		}

		/**
		 * Secrets (ssh-copy-id) → {@link State.KEY_INSTALLED} → {@link State.DONE}.
		 *
		 * Same expect → feed_child → expect shape as {@link SshLogin.login}.
		 * Passphrase once if set, then host password on later prompts.
		 */
		public override async void run() throws Error
		{
			this.terminal.spawn();
			var fed_phrase = false;
			while (this.current_state != State.KEY_INSTALLED) {
				if (!yield this.expect(State.WAIT_SSH_PASSWORD, 30000)) {
					if (this.current_state == State.KEY_INSTALLED) {
						break;
					}
					if (this.current_state == State.WAIT_HOST_CONFIRM
							|| this.current_state == State.WAIT_VERIFICATION_CODE) {
						continue;
					}
					throw new Error.TIMEOUT("setup key password timeout name=%s".printf(
						this.connection.name));
				}
				if (this.connection.passphrase.length > 0 && !fed_phrase) {
					this.terminal.terminal.feed_child((this.connection.passphrase + "\n").data);
					fed_phrase = true;
				} else {
					this.terminal.terminal.feed_child((this.connection.pass + "\n").data);
				}
				this.current_state = State.UNKNOWN;
				if (yield this.expect(State.KEY_INSTALLED, 60000)) {
					break;
				}
				if (this.current_state == State.WAIT_SSH_PASSWORD
						|| this.current_state == State.WAIT_VERIFICATION_CODE) {
					continue;
				}
				if (this.current_state == State.KEY_INSTALLED) {
					break;
				}
				throw new Error.TIMEOUT("setup key install timeout name=%s".printf(
					this.connection.name));
			}
			this.current_state = State.DONE;
		}
	}
}
