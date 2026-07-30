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
	 * Session-bus API for Guake toggle / quit (Shell extension + CLI).
	 *
	 * Owns ``org.roojs.RooTerm.DBus`` at ``/org/roojs/RooTerm/DBus``.
	 * Methods export as ``Toggle`` / ``Quit`` on the bus. Constructed from
	 * {@link Application.startup}; the Shell extension (15b) calls it for global F12.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.dbus = new DBus(this);
	 * // gdbus … --method org.roojs.RooTerm.DBus.Toggle
	 * }}}
	 */
	[DBus (name = "org.roojs.RooTerm.DBus")]
	public class DBus : GLib.Object
	{
		/**
		 * Owning {@link Application}.
		 */
		public Application application;

		/**
		 * Owns the session-bus name and registers this object.
		 *
		 * @param application Owning app
		 */
		public DBus(Application application)
		{
			this.application = application;
			GLib.Bus.own_name(
				GLib.BusType.SESSION,
				"org.roojs.RooTerm.DBus",
				GLib.BusNameOwnerFlags.NONE,
				(conn) => {
					try {
						conn.register_object("/org/roojs/RooTerm/DBus", this);
					} catch (GLib.IOError e) {
						GLib.warning("D-Bus register failed: %s", e.message);
					}
				},
				() => {
					GLib.debug("D-Bus name acquired");
				},
				() => {
					GLib.warning("D-Bus name lost");
				}
			);
		}

		/**
		 * Toggle main window: create if missing, else hide when visible / present when hidden.
		 */
		public void toggle()
		{
			if (this.application.active_window == null) {
				this.application.activate();
				return;
			}
			if (this.application.active_window.visible) {
				this.application.active_window.visible = false;
				return;
			}
			this.application.active_window.present();
		}

		/**
		 * Quit the application (Shell panel / ``rooterm --quit``).
		 */
		public void quit()
		{
			this.application.quit();
		}
	}
}
