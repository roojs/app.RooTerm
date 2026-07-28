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
	private static GLib.FileStream? debug_log_file = null;
	private static bool debug_log_in_progress = false;

	/**
	 * When true, debug-level messages go to stderr (file always receives them).
	 */
	public static bool debug_on = false;

	/**
	 * When true, critical log messages abort via {@link GLib.error}.
	 */
	public static bool debug_critical_enabled = false;

	/**
	 * Writes to ``~/.cache/rooterm/{app_id}.debug.log`` (and stderr when debug is on).
	 *
	 * Same pattern as OLLMchat ``ApplicationInterface.debug_log``.
	 *
	 * @param app_id Log file basename stem
	 * @param in_domain GLib log domain (empty if unset)
	 * @param level Log level flags
	 * @param message Log message text
	 */
	public static void debug_log(string app_id, string in_domain, GLib.LogLevelFlags level, string message)
	{
		if (debug_log_in_progress) {
			return;
		}

		var timestamp = (new GLib.DateTime.now_local()).format("%H:%M:%S.%f");
		var should_output = debug_on || (level & GLib.LogLevelFlags.LEVEL_CRITICAL) != 0;

		if (should_output) {
			GLib.stderr.printf(timestamp + ": " + level.to_string() + " : " + in_domain + " : " + message + "\n");
		}

		if ((level & GLib.LogLevelFlags.LEVEL_CRITICAL) != 0 && debug_critical_enabled) {
			GLib.error("Critical warning: [" + in_domain + "] " + message);
		}

		debug_log_in_progress = true;

		if (debug_log_file == null) {
			var log_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".cache", "rooterm"
			);
			var log_file_path = GLib.Path.build_filename(log_dir, app_id + ".debug.log");

			if (!GLib.FileUtils.test(log_dir, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(log_dir, 0755);
			}

			debug_log_file = GLib.FileStream.open(log_file_path, "w");
			if (debug_log_file == null) {
				GLib.stderr.printf("ERROR: FAILED TO OPEN DEBUG LOG FILE: Unable to open file stream\n");
				debug_log_in_progress = false;
				return;
			}
		}

		if (debug_log_file != null) {
			debug_log_file.puts(timestamp + ": " + level.to_string() + " : " + message + "\n");
			debug_log_file.flush();
		}
		debug_log_in_progress = false;
	}

	/**
	 * RooTerm GTK application: ``--debug`` logging and main window.
	 */
	public class Application : Adw.Application
	{
		public static bool opt_debug = false;
		public static bool opt_debug_critical = false;

		private const GLib.OptionEntry[] app_options = {
			{ "debug", 'd', 0, GLib.OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, GLib.OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ null }
		};

		/**
		 * Creates the application and installs the debug log handler.
		 */
		public Application()
		{
			Object(
				application_id: "org.roojs.rooterm",
				flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
			);
			Gtk.Window.set_default_icon_name("org.roojs.rooterm");

			GLib.Log.set_default_handler((dom, lvl, msg) => {
				RooTerm.debug_log("rooterm", dom != null ? dom : "", lvl, msg);
			});

			this.activate.connect(() => {
				var open = this.active_window;
				if (open != null) {
					open.present();
					return;
				}
				var window = new MainWindow(this);
				this.add_window(window);
				window.present();
			});
		}

		protected override int command_line(GLib.ApplicationCommandLine command_line)
		{
			opt_debug = false;
			opt_debug_critical = false;

			string[] args = command_line.get_arguments();
			var opt_context = new GLib.OptionContext(this.get_application_id());
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(app_options, null);

			try {
				unowned string[] unowned_args = args;
				opt_context.parse(ref unowned_args);
			} catch (GLib.OptionError e) {
				command_line.printerr("error: %s\n", e.message);
				command_line.printerr("Run '%s --help' to see a full list of available command line options.\n", args[0]);
				return 1;
			}

			RooTerm.debug_on = opt_debug;
			RooTerm.debug_critical_enabled = opt_debug_critical;

			this.hold();
			this.activate();
			this.release();

			return 0;
		}
	}
}
