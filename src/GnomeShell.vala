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
	 * RooTerm GNOME Shell extension (``rooterm@roojs.com``).
	 *
	 * Installs the bundled extension into the user extensions dir (unless a
	 * system copy is already present), enables it, and if Shell has not loaded
	 * it yet (common on Wayland until a session restart) shows a hint dialog.
	 *
	 * == Example ==
	 *
	 * {{{
	 * new GnomeShell(window).ensure();
	 * }}}
	 */
	public class GnomeShell : GLib.Object
	{
		/**
		 * Extension UUID (directory name under gnome-shell/extensions).
		 */
		public string uuid = "rooterm@roojs.com";

		/**
		 * Parent window for install-failure / restart hint dialogs.
		 */
		public Gtk.Window window { get; construct; }

		/**
		 * @param window Parent for extension dialogs
		 */
		public GnomeShell(Gtk.Window window)
		{
			Object(window: window);
		}

		/**
		 * Install from GResource if needed, enable when Shell knows it, else
		 * explain session restart.
		 */
		public void ensure()
		{
			var data_home = GLib.Environment.get_variable("XDG_DATA_HOME");
			if (data_home == null || data_home == "") {
				data_home = GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".local", "share");
			}
			var user_dir = GLib.Path.build_filename(data_home, "gnome-shell", "extensions", this.uuid);
			var user_meta = GLib.Path.build_filename(user_dir, "metadata.json");
			var system_meta = GLib.Path.build_filename(
				"/usr/share/gnome-shell/extensions", this.uuid, "metadata.json"
			);

			if (!GLib.FileUtils.test(system_meta, GLib.FileTest.IS_REGULAR)) {
				try {
					this.install(data_home, user_dir);
				} catch (GLib.Error e) {
					GLib.warning("Shell extension install failed: %s", e.message);
					var key = Config.load().toggle_key;
					var body = @"Could not install the RooTerm GNOME Shell extension:
$(e.message)

Global $(key) / panel Toggle will not work until this is fixed. You can still use this window, or run: rooterm --toggle";
					var alert = new Adw.AlertDialog("Shell extension install failed", body);
					alert.add_response("ok", "OK");
					alert.default_response = "ok";
					alert.close_response = "ok";
					alert.present(this.window);
					return;
				}
			}

			if (!GLib.FileUtils.test(user_meta, GLib.FileTest.IS_REGULAR)
					&& !GLib.FileUtils.test(system_meta, GLib.FileTest.IS_REGULAR)) {
				return;
			}

			var shell_knows = false;
			var enabled = false;
			try {
				var bus = GLib.Bus.get_sync(GLib.BusType.SESSION);
				var info_reply = bus.call_sync(
					"org.gnome.Shell.Extensions",
					"/org/gnome/Shell/Extensions",
					"org.gnome.Shell.Extensions",
					"GetExtensionInfo",
					new GLib.Variant("(s)", this.uuid),
					new GLib.VariantType("(a{sv})"),
					GLib.DBusCallFlags.NONE,
					-1,
					null
				);
				var info = info_reply.get_child_value(0);
				if (info.n_children() > 0) {
					shell_knows = true;
					var state = (int32) 0;
					info.lookup("state", "i", out state);
					enabled = (state == 1);
				}
			} catch (GLib.Error e) {
				GLib.debug("Shell extension check failed: %s", e.message);
			}

			if (enabled) {
				return;
			}

			if (!shell_knows) {
				this.show_restart_shell_messages(false);
				return;
			}

			try {
				var bus = GLib.Bus.get_sync(GLib.BusType.SESSION);
				var en_reply = bus.call_sync(
					"org.gnome.Shell.Extensions",
					"/org/gnome/Shell/Extensions",
					"org.gnome.Shell.Extensions",
					"EnableExtension",
					new GLib.Variant("(s)", this.uuid),
					new GLib.VariantType("(b)"),
					GLib.DBusCallFlags.NONE,
					-1,
					null
				);
				en_reply.get("(b)", out enabled);
			} catch (GLib.Error e) {
				GLib.debug("Shell extension enable failed: %s", e.message);
			}
			if (enabled) {
				return;
			}
			this.show_restart_shell_messages(true);
		}

		/**
		 * Show why the global toggle / panel Toggle is not active yet.
		 *
		 * @param shell_knows Whether Shell already lists this UUID
		 */
		public void show_restart_shell_messages(bool shell_knows)
		{
			var key = Config.load().toggle_key;
			var middle = @"On Wayland, log out and back in (or restart the session) once so Shell picks up the new extension. After that, $(key) and the panel icon work.

";
			if (GLib.Environment.get_variable("XDG_SESSION_TYPE") != "wayland" && shell_knows) {
				middle = @"Try Extensions → enable \"RooTerm\", or: gnome-extensions enable $(this.uuid)

";
			}
			var body = @"RooTerm's GNOME Shell extension is installed (global $(key) / panel Toggle), but GNOME Shell has not loaded it yet.

$(middle)Until then you can use this window normally, or run: rooterm --toggle";
			var alert = new Adw.AlertDialog("Shell extension needs a session restart", body);
			alert.add_response("ok", "OK");
			alert.default_response = "ok";
			alert.close_response = "ok";
			alert.present(this.window);
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
				"stylesheet.css",
				"schemas/org.gnome.shell.extensions.rooterm.gschema.xml"
			};
			foreach (var name in names) {
				var data = GLib.resources_lookup_data(
					"/rooterm/extension/" + name, GLib.ResourceLookupFlags.NONE
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
