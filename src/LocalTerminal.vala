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
	 * Local PTY terminal ({@link Terminal} subclass).
	 * Spawns ``$SHELL`` in a working directory; exit closes the tab immediately.
	 * Path labels follow {@link TerminalStream} cwd updates via {@link label_changed}.
	 */
	public class LocalTerminal : Terminal
	{
		/**
		 * Directory to spawn in (home when empty).
		 */
		public string start_cwd = "";

		/**
		 * Build a local shell tab (call {@link spawn} to start).
		 *
		 * @param connection Localhost connection
		 * @param font Pango font string
		 * @param cwd Working directory (home when empty)
		 */
		public LocalTerminal(Connection connection, string font = "Monospace 9", string cwd = "")
		{
			base(connection, font);
			this.start_cwd = cwd;
			this.cwd = cwd;
			this.stream = new TerminalStream(this);
			this.terminal.child_exited.connect((status) => {
				GLib.debug("local shell exited status=%d", status);
				if (this.settle_timeout != 0) {
					GLib.Source.remove(this.settle_timeout);
					this.settle_timeout = 0;
				}
				this.child_pid = -1;
				this.close_in(0);
			});
		}

		/**
		 * {@inheritDoc}
		 */
		public override string label()
		{
			if (this.cwd.length > 0) {
				return this.cwd;
			}
			if (this.start_cwd.length > 0) {
				return this.start_cwd;
			}
			return GLib.Environment.get_home_dir();
		}

		/**
		 * Spawn ``$SHELL`` (or ``/bin/bash``) in {@link start_cwd} or home.
		 */
		public override void spawn()
		{
			var shell = GLib.Environment.get_variable("SHELL");
			if (shell == null || shell.length == 0) {
				shell = "/bin/bash";
			}
			var dir = this.start_cwd;
			if (dir.length == 0) {
				dir = GLib.Environment.get_home_dir();
			}
			if (dir != this.cwd) {
				this.cwd = dir;
				this.label_changed();
			}
			string[] argv = { shell };
			GLib.debug("local spawn shell=%s cwd=%s", shell, dir);
			this.terminal.spawn_async(
				Vte.PtyFlags.DEFAULT,
				dir,
				argv,
				null,
				GLib.SpawnFlags.SEARCH_PATH,
				null,
				-1,
				null,
				(term, pid, error) => {
					if (error != null) {
						this.child_pid = -1;
						GLib.warning("local spawn failed: %s", error.message);
						var fail = "spawn failed: " + error.message + "\r\n";
						this.terminal.feed(fail.data);
						return;
					}
					this.child_pid = pid;
					GLib.debug("local pid=%d", pid);
				}
			);
		}
	}
}
