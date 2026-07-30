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
	 * Methods export as ``Toggle`` / ``Quit`` / ``About`` on the bus. Constructed from
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
		 * Fired after a successful show (Shell extension docks under the panel).
		 */
		public signal void shown();

		/**
		 * Toggle main window: create if missing, else hide when visible / present when hidden.
		 */
		public void toggle()
		{
			if (this.application.window == null) {
				this.application.activate();
				this.shown();
				return;
			}
			var window = this.application.window;
			if (window.visible) {
				window.visible = false;
				return;
			}
			window.visible = true;
			window.present();
			window.set_default_size(
				window.monitor_geo.width * window.config.width / 100,
				window.monitor_geo.height * window.config.height / 100
			);
			this.shown();
		}

		/**
		 * Quit the application (Shell panel / ``rooterm --quit``).
		 */
		public void quit()
		{
			this.application.quit();
		}

		/**
		 * Present {@link Adw.AboutDialog} (Shell panel menu).
		 */
		public void about()
		{
			if (this.application.window == null) {
				this.application.activate();
			}
			var about = new Adw.AboutDialog() {
				application_name = "Roo Term",
				application_icon = "org.roojs.rooterm",
				developer_name = "Alan Knowles",
				version = "0.1.0",
				website = "https://github.com/roojs/app.RooTerm",
				issue_url = "https://github.com/roojs/app.RooTerm/issues",
				license_type = Gtk.License.LGPL_3_0,
				comments = "Guake-style drop-down terminal with Ásbrú-cm-like hosts."
			};
			about.present(this.application.window);
		}
	}
}
