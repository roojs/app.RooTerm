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
	 * Compares the bundled ``metadata.json`` ``version`` to the installed
	 * copy; installs or upgrades into the user extensions dir when newer,
	 * enables it, and if Shell has not loaded the new code yet (common on
	 * Wayland until a session restart) shows a hint dialog.
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
		 * Install or upgrade from GResource when the bundled version is
		 * newer, enable when Shell knows it, else explain session restart.
		 * Also ensures a settings-daemon custom shortcut for global toggle
		 * (same pattern as Guake — works without relying on Shell keybindings alone).
		 */
		public void ensure()
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
					"/rooterm/extension/metadata.json", GLib.ResourceLookupFlags.NONE
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

			var updated = false;
			if (bundled > 0 && installed < bundled) {
				try {
					this.install(data_home, user_dir);
					updated = true;
				} catch (GLib.Error e) {
					GLib.warning("Shell extension install failed: %s", e.message);
					var key = Config.load().toggle_key;
					var body = @"Could not install the RooTerm GNOME Shell extension:
$(e.message)

Global $(key) / panel icon will not work until this is fixed. You can still use this window, or run: rooterm --toggle";
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

			if (updated) {
				if (!enabled) {
					GLib.warning(
						"Shell extension updated; reload Shell (Alt+F2, r) for the panel icon. F12 still works via rooterm --toggle."
					);
				}
				return;
			}

			if (enabled) {
				return;
			}

			if (!shell_knows) {
				GLib.warning(
					"Shell extension not loaded yet; reload Shell (Alt+F2, r) for the panel icon. F12 still works via rooterm --toggle."
				);
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
			GLib.warning(
				"Could not enable Shell extension; panel icon unavailable. F12 still works via rooterm --toggle."
			);
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
