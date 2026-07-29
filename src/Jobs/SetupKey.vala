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
	 * ``ssh-copy-id``: password → {@link State.KEY_INSTALLED}.
	 *
	 * Sets ``install_key`` on {@link Job.stream} in the ctor. {@link KeyDialog} stays outside.
	 */
	public class SetupKey : SshLogin
	{
		/**
		 * Identity from ``ssh-copy-id`` success (ConnDialog stages it).
		 */
		public string installed_identity = "";

		private ulong key_installed_id = 0;

		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 */
		public SetupKey(MainWindow window, Connection connection)
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
		 * Password (ssh-copy-id) → {@link State.KEY_INSTALLED} → {@link State.DONE}.
		 */
		public override async void run() throws JobError
		{
			this.terminal.spawn();
			yield this.expect(State.WAIT_SSH_PASSWORD, 30000);
			this.terminal.terminal.feed_child((this.connection.pass + "\n").data);
			yield this.expect(State.KEY_INSTALLED, 60000);
			this.current_state = State.DONE;
		}
	}
}
