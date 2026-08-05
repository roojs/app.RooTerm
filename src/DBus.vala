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
	 * Wire names are lowercase / snake_case (``toggle``, ``quit``, ``config_update``, …).
	 * Constructed from {@link Application.startup}; the Shell extension calls it for global toggle.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.dbus = new DBus(this);
	 * // gdbus … --method org.roojs.RooTerm.DBus.toggle
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
		 * True after the user confirms quit (or quit with no open terminals).
		 * Lets {@link MainWindow} ``close_request`` allow destroy without a second dialog.
		 */
		public bool quitting = false;

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
					var window = this.application.window;
					if (window != null && window.is_docked && window.visible) {
						GLib.debug("redock after name acquired dock_mode=%d", (int) this.dock_mode);
						this.redock();
					}
				},
				() => {
					GLib.warning("D-Bus name lost");
				}
			);
		}

		/**
		 * Cue the Shell extension to (re)apply underbar dock geometry on main.
		 */
		[DBus (name = "redock")]
		public signal void redock();

		/**
		 * True when {@link MainWindow} is in underbar drop-down mode.
		 * Set from the window when mode is chosen; Shell docks only when true.
		 * Must be a property (not a field) so it is exported on D-Bus as ``dock_mode``.
		 */
		[DBus (name = "dock_mode")]
		public bool dock_mode { get; set; default = false; }

		/**
		 * Call a method on ``org.roojs.RooTerm.Shell`` (try/catch; logs failures).
		 *
		 * Not exported on ``org.roojs.RooTerm.DBus``.
		 *
		 * @param method D-Bus method (``register`` / ``show`` / ``hide`` / ``toggle`` / ``exited``)
		 * @param parameters Method arguments variant
		 */
		[DBus (visible = false)]
		public void call(string method, GLib.Variant parameters)
		{
			try {
				GLib.Bus.get_sync(GLib.BusType.SESSION, null).call_sync(
					"org.roojs.RooTerm.Shell",
					"/org/roojs/RooTerm/Shell", "org.roojs.RooTerm.Shell",
					method, parameters,
					null, GLib.DBusCallFlags.NONE, 2000, null
				);
			} catch (GLib.Error e) {
				GLib.debug("Shell %s: %s", method, e.message);
			}
		}

		/**
		 * Async Shell call — use when the main loop must keep running (prefs
		 * show/hide; avoids ``call_sync`` deadlock with Shell ``skip_taskbar``).
		 *
		 * Not exported on ``org.roojs.RooTerm.DBus``.
		 *
		 * @param method D-Bus method (``register`` / ``show`` / ``hide`` / …)
		 * @param parameters Method arguments variant
		 */
		[DBus (visible = false)]
		public void call_async(string method, GLib.Variant parameters)
		{
			try {
				var bus = GLib.Bus.get_sync(GLib.BusType.SESSION, null);
				bus.call.begin(
					"org.roojs.RooTerm.Shell",
					"/org/roojs/RooTerm/Shell", "org.roojs.RooTerm.Shell",
					method, parameters,
					null, GLib.DBusCallFlags.NONE, -1, null,
					(s, res) => {
						try {
							bus.call.end(res);
						} catch (GLib.Error e) {
							GLib.debug("Shell %s: %s", method, e.message);
						}
					}
				);
			} catch (GLib.Error e) {
				GLib.debug("Shell %s: %s", method, e.message);
			}
		}

		/**
		 * Toggle main window: create if missing, else Shell ``toggle('main')``.
		 */
		[DBus (name = "toggle")]
		public void toggle()
		{
			if (this.application.window == null) {
				this.application.activate();
				return;
			}
			var window = this.application.window;
			// Setup/restart AlertDialog is parented on the window — hide would dismiss it.
			if (window.block_toggle) {
				return;
			}
			// Shell may have become ready while the setup window stayed visible (e.g. after
			// Alt+F2 ``r``). Ensure (enable if needed) then remorph; if still setup, skip toggle.
			if (!window.is_docked) {
				window.shell.ensure(() => {
					if (!window.shell.is_ready) {
						return;
					}
					if (!window.is_docked) {
						window.show_docked();
					}
					this.redock();
				});
				if (window.block_toggle || !window.is_docked) {
					return;
				}
			}
			window.terminal_menu.popdown();
			this.call("toggle", new GLib.Variant("(s)", "main"));
		}

		/**
		 * Quit the application (Shell panel / ``rooterm --quit`` / VTE menu).
		 * Confirms when the main window exists, unless ``force`` (WaylandClient handoff).
		 *
		 * @param force Skip the confirm dialog and quit immediately
		 */
		[DBus (name = "quit")]
		public void quit(bool force = false)
		{
			if (this.quitting || force) {
				this.quitting = true;
				this.call(
					"exited",
					new GLib.Variant("(s)", this.application.application_id)
				);
				this.application.quit();
				return;
			}
			var window = this.application.window;
			if (window == null) {
				this.quitting = true;
				this.call(
					"exited",
					new GLib.Variant("(s)", this.application.application_id)
				);
				this.application.quit();
				return;
			}
			var n = 0;
			for (var child = window.host_stack.pages.get_first_child();
					child != null; child = child.get_next_sibling()) {
				var page = child as Host.Page;
				if (page == null) {
					continue;
				}
				n += page.tab_view.n_pages;
			}
			var alert = new Adw.AlertDialog("Quit Roo Term?",
				n == 1 ? "There is 1 open terminal."
					: "There are " + n.to_string() + " open terminals.");
			alert.add_response("cancel", "Cancel");
			alert.add_response("quit", "Quit");
			alert.set_response_appearance("quit", Adw.ResponseAppearance.DESTRUCTIVE);
			alert.default_response = "cancel";
			alert.close_response = "cancel";
			alert.response.connect((response) => {
				if (response != "quit") {
					return;
				}
				this.quitting = true;
				this.call(
					"exited",
					new GLib.Variant("(s)", this.application.application_id)
				);
				this.application.quit();
			});
			alert.present(window);
		}

		/**
		 * Set X11 skip-taskbar/pager for a Shell-owned window role.
		 *
		 * Shell clears this briefly before minimize so Mutter allows it, then
		 * sets it again so overview and Alt-Tab stay clear. On GNOME 48, Meta
		 * has no hide_from_window_list for ordinary app windows.
		 *
		 * @param role ``main`` / ``preferences``
		 * @param skip True to hide from task lists
		 */
		[DBus (name = "skip_taskbar")]
		public void skip_taskbar(string role, bool skip)
		{
			if (this.application.window == null) {
				return;
			}
			var target = this.application.window as Gtk.Window;
			switch (role) {
				case "main":
					target = this.application.window;
					break;

				case "preferences":
					target = this.application.window.preferences_editor;
					break;

				default:
					return;
			}
			// Wayland / unrealized: no Gdk.X11.Surface (external API).
			var x11 = target.get_surface() as Gdk.X11.Surface;
			if (x11 == null) {
				return;
			}
			x11.set_skip_taskbar_hint(skip);
			x11.set_skip_pager_hint(skip);
		}

		/**
		 * Show {@link Dialog.Preferences} (Shell panel menu / ``Ctrl+,``).
		 */
		[DBus (name = "preferences")]
		public void preferences()
		{
			if (this.application.window == null) {
				this.application.activate();
			}
			var window = this.application.window;
			if (window == null) {
				return;
			}
			var prefs = window.preferences_editor;
			prefs.fill();
			prefs.present();
			// map → register (idle). Async show — call_sync deadlocks with Shell skip_taskbar.
			GLib.Timeout.add(50, () => {
				this.call_async("show", new GLib.Variant("(s)", "preferences"));
				return false;
			});
		}

		/**
		 * Set one chrome property from the preferences process.
		 *
		 * @param key Hyphenated GObject name (``opacity``, ``toggle-key``, …)
		 * @param value Always a string (ints as decimal text)
		 */
		[DBus (name = "config_update")]
		public void config_update(string key, string value)
		{
			if (this.application.window == null) {
				return;
			}
			var config = this.application.window.config;
			var pspec = config.find_property(key);
			if (pspec == null) {
				GLib.warning("unknown config key: %s", key);
				return;
			}
			var parsed = Value(pspec.value_type);
			switch (pspec.value_type) {
				case GLib.Type.INT:
					parsed.set_int(int.parse(value));
					break;

				case GLib.Type.STRING:
					parsed.set_string(value);
					break;

				default:
					GLib.warning("unsupported config type for %s", key);
					return;
			}
			((GLib.Object) config).set_property(key, parsed);
			config.save();
		}

		/**
		 * Present {@link Adw.AboutDialog} (Shell panel menu).
		 */
		[DBus (name = "about")]
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
