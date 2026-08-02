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
	 * Continue after {@link GnomeShell.ensure} finishes (and any dialog is closed).
	 */
	public delegate void GnomeShellDone();

	/**
	 * RooTerm GNOME Shell extension (``rooterm@roojs.com``).
	 *
	 * Compares the bundled ``metadata.json`` ``version`` to the installed
	 * copy; installs or upgrades into the user extensions dir when newer,
	 * enables it, and if Shell has not loaded the new code yet (common on
	 * Wayland until a session restart) shows a hint dialog.
	 *
	 * == Example ==
	 *
	 * {{{
	 * new GnomeShell(main_window).ensure(() => { … });
	 * }}}
	 */
	public class GnomeShell : GLib.Object
	{
		/**
		 * Extension UUID (directory name under gnome-shell/extensions).
		 */
		public string uuid = "rooterm@roojs.com";

		/**
		 * Parent for install-failure / restart {@link Adw.AlertDialog}s.
		 * Null only for headless ``--toggle-key`` (settings write; no UI).
		 */
		public MainWindow? window { get; construct; default = null; }

		/**
		 * True when Shell has the extension enabled at the bundled version.
		 * Set in the constructor (and refreshed by {@link ensure}).
		 */
		public bool is_ready = false;

		/**
		 * @param window Parent for extension dialogs, or null for settings-only
		 */
		public GnomeShell(MainWindow? window = null)
		{
			Object(window: window);

			var bundled = 0;
			try {
				var bundled_data = GLib.resources_lookup_data(
					"/extension/metadata.json", GLib.ResourceLookupFlags.NONE
				);
				var bundled_parser = new Json.Parser();
				bundled_parser.load_from_data(
					(string) bundled_data.get_data(), (ssize_t) bundled_data.get_size()
				);
				bundled = (int) bundled_parser.get_root().get_object().get_int_member("version");
			} catch (GLib.Error e) {
				GLib.debug("Shell extension bundled metadata: %s", e.message);
			}
			if (bundled <= 0) {
				return;
			}

			var data_home = GLib.Environment.get_variable("XDG_DATA_HOME");
			if (data_home == null || data_home == "") {
				data_home = GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".local", "share");
			}
			var user_meta = GLib.Path.build_filename(
				data_home, "gnome-shell", "extensions", this.uuid, "metadata.json"
			);
			var system_meta = GLib.Path.build_filename(
				"/usr/share/gnome-shell/extensions", this.uuid, "metadata.json"
			);
			if (!GLib.FileUtils.test(user_meta, GLib.FileTest.IS_REGULAR)
					&& !GLib.FileUtils.test(system_meta, GLib.FileTest.IS_REGULAR)) {
				return;
			}
			try {
				var bus = GLib.Bus.get_sync(GLib.BusType.SESSION);
				var info_reply = bus.call_sync(
					"org.gnome.Shell.Extensions", "/org/gnome/Shell/Extensions",
					"org.gnome.Shell.Extensions", "GetExtensionInfo",
					new GLib.Variant("(s)", this.uuid),
					new GLib.VariantType("(a{sv})"),
					GLib.DBusCallFlags.NONE,
					-1,
					null
				);
				var info = info_reply.get_child_value(0);
				if (info.n_children() == 0) {
					return;
				}
				// Shell sends state/version as doubles over D-Bus.
				var state_d = 0.0;
				var version_d = 0.0;
				info.lookup("state", "d", out state_d);
				info.lookup("version", "d", out version_d);
				this.is_ready = ((int) state_d == 1) && ((int) version_d >= bundled);
				GLib.debug(
					"Shell extension ctor ready=%d state=%d version=%d bundled=%d",
					(int) this.is_ready, (int) state_d, (int) version_d, bundled
				);
			} catch (GLib.Error e) {
				GLib.debug("Shell extension check failed: %s", e.message);
			}
		}

		/**
		 * Install or upgrade from GResource when the bundled version is
		 * newer, enable when Shell knows it, else explain session restart.
		 * Also ensures a settings-daemon custom shortcut for global toggle
		 * (same pattern as Guake — works without relying on Shell keybindings alone).
		 *
		 * Calls ``done`` when checks finish (after any hint dialog is dismissed).
		 *
		 * @param done Continue startup (e.g. after dialogs)
		 */
		public void ensure(owned GnomeShellDone done)
		{
			try {
				this.ensure_toggle_binding(Config.load().toggle_key);
			} catch (GLib.Error e) {
				GLib.warning("toggle binding: %s", e.message);
			}

			var data_home = GLib.Environment.get_variable("XDG_DATA_HOME");
			if (data_home == null || data_home == "") {
				data_home = GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".local", "share");
			}
			var user_dir = GLib.Path.build_filename(data_home, "gnome-shell", "extensions", this.uuid);
			var user_meta = GLib.Path.build_filename(user_dir, "metadata.json");
			var system_meta = GLib.Path.build_filename(
				"/usr/share/gnome-shell/extensions", this.uuid, "metadata.json"
			);

			var bundled = 0;
			try {
				var bundled_data = GLib.resources_lookup_data(
					"/extension/metadata.json", GLib.ResourceLookupFlags.NONE
				);
				var bundled_parser = new Json.Parser();
				bundled_parser.load_from_data(
					(string) bundled_data.get_data(), (ssize_t) bundled_data.get_size()
				);
				bundled = (int) bundled_parser.get_root().get_object().get_int_member("version");
			} catch (GLib.Error e) {
				GLib.warning("Shell extension bundled metadata: %s", e.message);
			}

			var installed = 0;
			foreach (var path in new string[] { user_meta, system_meta }) {
				if (!GLib.FileUtils.test(path, GLib.FileTest.IS_REGULAR)) {
					continue;
				}
				try {
					var installed_parser = new Json.Parser();
					installed_parser.load_from_file(path);
					installed = (int) installed_parser.get_root().get_object().get_int_member("version");
				} catch (GLib.Error e) {
					GLib.debug("Shell extension metadata %s: %s", path, e.message);
				}
				break;
			}

			if (bundled > 0 && installed < bundled) {
				try {
					this.install(data_home, user_dir);
				} catch (GLib.Error e) {
					GLib.warning("Shell extension install failed: %s", e.message);
					this.alert(
						"Shell extension install failed",
						@"Could not install the RooTerm GNOME Shell extension:
$(e.message)",
						(owned) done
					);
					return;
				}
			}

			if (!GLib.FileUtils.test(user_meta, GLib.FileTest.IS_REGULAR)
					&& !GLib.FileUtils.test(system_meta, GLib.FileTest.IS_REGULAR)) {
				done();
				return;
			}

			var shell_knows = false;
			var enabled = false;
			var shell_version = 0;
			try {
				var bus = GLib.Bus.get_sync(GLib.BusType.SESSION);
				var info_reply = bus.call_sync(
					"org.gnome.Shell.Extensions", "/org/gnome/Shell/Extensions",
					"org.gnome.Shell.Extensions", "GetExtensionInfo",
					new GLib.Variant("(s)", this.uuid),
					new GLib.VariantType("(a{sv})"),
					GLib.DBusCallFlags.NONE,
					-1,
					null
				);
				var info = info_reply.get_child_value(0);
				if (info.n_children() > 0) {
					shell_knows = true;
					// Shell sends state/version as doubles over D-Bus.
					var state_d = 0.0;
					var version_d = 0.0;
					info.lookup("state", "d", out state_d);
					info.lookup("version", "d", out version_d);
					enabled = ((int) state_d == 1);
					shell_version = (int) version_d;
				}
			} catch (GLib.Error e) {
				GLib.debug("Shell extension check failed: %s", e.message);
			}
			this.is_ready = enabled && bundled > 0 && shell_version >= bundled;
			GLib.debug(
				"Shell extension ensure ready=%d enabled=%d shell_ver=%d bundled=%d knows=%d",
				(int) this.is_ready, (int) enabled, shell_version, bundled, (int) shell_knows
			);

			// On-disk update does not reload Shell — running version stays old until restart.
			if (shell_knows && bundled > 0 && shell_version < bundled) {
				this.is_ready = false;
				GLib.debug(
					"Shell extension version shell=%d bundled=%d — needs reload",
					shell_version, bundled
				);
				this.alert("Shell extension needs a session restart", "", (owned) done);
				return;
			}

			if (this.is_ready) {
				done();
				return;
			}

			if (!shell_knows) {
				this.alert("Shell extension needs a session restart", "", (owned) done);
				return;
			}

			var enable_error = "";
			try {
				var bus = GLib.Bus.get_sync(GLib.BusType.SESSION);
				var en_reply = bus.call_sync(
					"org.gnome.Shell.Extensions", "/org/gnome/Shell/Extensions",
					"org.gnome.Shell.Extensions", "EnableExtension",
					new GLib.Variant("(s)", this.uuid),
					new GLib.VariantType("(b)"),
					GLib.DBusCallFlags.NONE,
					-1,
					null
				);
				en_reply.get("(b)", out enabled);
			} catch (GLib.Error e) {
				enable_error = e.message;
				GLib.debug("Shell extension enable failed: %s", e.message);
			}
			this.is_ready = enabled && bundled > 0 && shell_version >= bundled;
			if (enabled && shell_version < bundled) {
				this.is_ready = false;
				this.alert("Shell extension needs a session restart", "", (owned) done);
				return;
			}
			if (this.is_ready) {
				done();
				return;
			}
			this.alert(
				"Shell extension not enabled",
				@"Could not enable the extension automatically.

Open the Extensions app and turn on RooTerm, or run:
gnome-extensions enable $(this.uuid)"
					+ (enable_error == "" ? "" : @"

($(enable_error))"),
				(owned) done
			);
		}

		/**
		 * Present a one-button OK {@link Adw.AlertDialog} on {@link window}.
		 *
		 * Empty ``detail`` → session-restart body (Wayland logout vs Alt+F2 ``r``).
		 * Otherwise ``detail`` plus the shared toggle-key / still-usable footer.
		 * Calls ``done`` when the dialog is dismissed.
		 *
		 * @param title Dialog heading
		 * @param detail Optional lead-in; empty means restart instructions
		 * @param done Continue after OK
		 */
		public void alert(string title, string detail, owned GnomeShellDone done)
		{
			var key = Config.load().toggle_key;
			var body = @"$(detail)

Global $(key) / panel icon will not work until this is fixed. You can still use this window, or run: rooterm --toggle";
			if (detail == "") {
				var middle = "You are using Wayland, so unfortunately the only way is to log out and log in again.";
				if (GLib.Environment.get_variable("XDG_SESSION_TYPE") != "wayland") {
					middle = "Press Alt+F2, type r, and press Enter — then click OK here.";
				}
				body = @"$(middle)

RooTerm updated the extension on disk, but GNOME Shell is still running the old code until you reload.

After reload, click OK to switch this window to the drop-down. Then $(key) and the panel icon will work.";
			}
			var dialog = new Adw.AlertDialog(title, body);
			dialog.add_response("ok", "OK");
			dialog.default_response = "ok";
			dialog.close_response = "ok";
			this.window.block_toggle = true;
			// Restart hint: after Alt+F2 ``r`` / logout, re-run ensure (EnableExtension)
			// instead of only probing is_ready — and auto-finish when Shell catches up.
			var restart_hint = detail == "";
			var poll_id = 0u;
			if (restart_hint) {
				poll_id = GLib.Timeout.add_seconds(1, () => {
					if (new GnomeShell(this.window).is_ready) {
						dialog.close();
						return false;
					}
					return true;
				});
			}
			dialog.response.connect(() => {
				if (poll_id != 0) {
					GLib.Source.remove(poll_id);
					poll_id = 0;
				}
				this.window.block_toggle = false;
				if (restart_hint) {
					this.ensure((owned) done);
					return;
				}
				done();
			});
			dialog.present(this.window);
		}

		/**
		 * Own ``rooterm --toggle`` custom media-keys shortcut (does not touch other apps).
		 *
		 * @param key Accelerator string (e.g. ``F12``)
		 * @throws GLib.Error On settings write failure
		 */
		public void ensure_toggle_binding(string key) throws GLib.Error
		{
			var media = new GLib.Settings("org.gnome.settings-daemon.plugins.media-keys");
			var paths = media.get_strv("custom-keybindings");
			string? ours = null;
			foreach (var path in paths) {
				var slot = new GLib.Settings.with_path(
					"org.gnome.settings-daemon.plugins.media-keys.custom-keybinding", path
				);
				if (slot.get_string("command") == "rooterm --toggle"
						|| slot.get_string("name") == "RooTerm") {
					ours = path;
					break;
				}
			}
			if (ours == null) {
				var n = 0;
				while (true) {
					var candidate = @"/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$(n)/";
					var taken = false;
					foreach (var path in paths) {
						if (path == candidate) {
							taken = true;
							break;
						}
					}
					if (!taken) {
						ours = candidate;
						break;
					}
					n++;
				}
				string[] next = {};
				foreach (var path in paths) {
					next += path;
				}
				next += ours;
				media.set_strv("custom-keybindings", next);
			}
			var slot = new GLib.Settings.with_path(
				"org.gnome.settings-daemon.plugins.media-keys.custom-keybinding", ours
			);
			slot.set_string("name", "RooTerm");
			slot.set_string("command", "rooterm --toggle");
			slot.set_string("binding", key);
			// Same accelerator on another custom slot (e.g. leftover Guake) shadows us.
			foreach (var path in paths) {
				if (path == ours) {
					continue;
				}
				var other = new GLib.Settings.with_path(
					"org.gnome.settings-daemon.plugins.media-keys.custom-keybinding", path
				);
				if (other.get_string("binding") == key) {
					other.set_string("binding", "");
					GLib.debug("cleared conflicting binding path=%s key=%s", path, key);
				}
			}
			// Extension schema: panel tooltip only (no wm grab).
			try {
				var ext = new GLib.Settings("org.gnome.shell.extensions.rooterm");
				string[] keys = { key };
				ext.set_strv("toggle", keys);
			} catch (GLib.Error e) {
				GLib.debug("extension toggle label: %s", e.message);
			}
		}

		/**
		 * Export a portal-style window handle and ``Register`` with
		 * ``org.roojs.RooTerm.Shell``. Retries D-Bus when the handle is
		 * already known (Shell bus may appear after first map).
		 *
		 * @param window Mapped window with a native surface
		 * @param role ``main`` / ``preferences`` / ``connection``
		 */
		public void register(Gtk.Window window, string role)
		{
			var existing = window.get_data<string>("rooterm-shell-handle");
			if (existing != null) {
				GLib.debug("Shell handle retry role=%s %s", role, existing);
				this.window.dbus.call("Register", new GLib.Variant("(ss)", role, existing));
				return;
			}
			var surface = window.get_surface();
			if (surface == null) {
				return;
			}
			var x11_surface = surface as Gdk.X11.Surface;
			if (x11_surface != null) {
				var handle = "x11:%x".printf((uint) x11_surface.get_xid());
				window.set_data("rooterm-shell-handle", handle.dup());
				GLib.debug("Shell handle role=%s %s", role, handle);
				this.window.dbus.call("Register", new GLib.Variant("(ss)", role, handle));
				return;
			}
			var wl_toplevel = surface as Gdk.Wayland.Toplevel;
			if (wl_toplevel == null) {
				return;
			}
			if (!wl_toplevel.export_handle((toplevel, h) => {
				var handle = "wayland:" + h;
				window.set_data("rooterm-shell-handle", handle.dup());
				GLib.debug("Shell handle role=%s %s", role, handle);
				this.window.dbus.call("Register", new GLib.Variant("(ss)", role, handle));
			})) {
				GLib.warning("Shell export_handle failed role=%s", role);
			}
		}

		/**
		 * Copy the bundled extension into the user extensions dir and compile schemas.
		 *
		 * @param data_home XDG data home (e.g. ``~/.local/share``)
		 * @param user_dir Destination ``…/extensions/rooterm@roojs.com``
		 * @throws GLib.Error If a file copy or ``glib-compile-schemas`` fails
		 */
		public void install(string data_home, string user_dir) throws GLib.Error
		{
			GLib.DirUtils.create_with_parents(GLib.Path.build_filename(user_dir, "schemas"), 0755);
			string[] names = {
				"metadata.json",
				"extension.js",
				"Const.js",
				"Indicator.js",
				"ShellService.js",
				"ShellIface.xml",
				"Dock.js",
				"stylesheet.css",
				"schemas/org.gnome.shell.extensions.rooterm.gschema.xml"
			};
			foreach (var name in names) {
				var data = GLib.resources_lookup_data(
					"/extension/" + name, GLib.ResourceLookupFlags.NONE
				);
				GLib.File.new_for_path(GLib.Path.build_filename(user_dir, name)).replace_contents(
					data.get_data(), null, false, GLib.FileCreateFlags.REPLACE_DESTINATION, null
				);
			}
			var ext_schemas = GLib.Path.build_filename(user_dir, "schemas");
			GLib.Process.spawn_command_line_sync("glib-compile-schemas " + ext_schemas);
			var glib_schemas = GLib.Path.build_filename(data_home, "glib-2.0", "schemas");
			GLib.DirUtils.create_with_parents(glib_schemas, 0755);
			GLib.File.new_for_path(
				GLib.Path.build_filename(ext_schemas, "org.gnome.shell.extensions.rooterm.gschema.xml")
			).copy(
				GLib.File.new_for_path(
					GLib.Path.build_filename(glib_schemas, "org.gnome.shell.extensions.rooterm.gschema.xml")
				),
				GLib.FileCopyFlags.OVERWRITE
			);
			GLib.Process.spawn_command_line_sync("glib-compile-schemas " + glib_schemas);
		}
	}
}
