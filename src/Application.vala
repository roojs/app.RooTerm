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
	 * RooTerm GTK application: ``--debug`` logging, session-bus {@link DBus}, main window.
	 *
	 * Daemon-style: {@link hold} keeps the process up when the window is hidden
	 * or closed; quit via {@link DBus.quit} / ``rooterm --quit``.
	 *
	 * == Example ==
	 *
	 * {{{
	 * rooterm --toggle
	 * rooterm --toggle-key F1
	 * rooterm --quit
	 * }}}
	 */
	public class Application : Adw.Application
	{
		public static bool opt_debug = false;
		public static bool opt_debug_critical = false;
		public static bool opt_toggle = false;
		public static bool opt_quit = false;
		public static string opt_toggle_key = "";

		/**
		 * Session-bus object (registered under org.roojs.RooTerm.DBus).
		 */
		public DBus dbus;

		/**
		 * Sole drop-down window (kept when hidden; {@link Gtk.Application.active_window} is null then).
		 */
		public MainWindow? window;

		/**
		 * True when this process is the preferences app (``--preferences``).
		 */
		public bool is_preferences = false;

		private const GLib.OptionEntry[] app_options = {
			{ "debug", 'd', 0, GLib.OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, GLib.OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "toggle", 0, 0, GLib.OptionArg.NONE, ref opt_toggle, "Show or hide the main window", null },
			{ "quit", 0, 0, GLib.OptionArg.NONE, ref opt_quit, "Quit the running RooTerm", null },
			{ "toggle-key", 0, 0, GLib.OptionArg.STRING, ref opt_toggle_key, "Set global toggle key (e.g. F12)", "KEY" },
			{ null }
		};

		/**
		 * Creates the application and installs debug logging.
		 * Session-bus {@link DBus} + daemon {@link hold} run in {@link startup} (primary only).
		 *
		 * @param is_preferences True → prefs app id; false → main
		 */
		public Application(bool is_preferences = false)
		{
			Object(
				application_id: is_preferences
					? "org.roojs.rooterm.preferences"
					: "org.roojs.rooterm",
				flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
			);
			this.is_preferences = is_preferences;
			Gtk.Window.set_default_icon_name("org.roojs.rooterm");

			GLib.Log.set_default_handler((dom, lvl, msg) => {
				RooTerm.debug_log("rooterm", dom != null ? dom : "", lvl, msg);
			});
		}

		/**
		 * Primary only: create session-bus {@link DBus} and hold so hide/close does not quit.
		 */
		protected override void startup()
		{
			base.startup();
			this.dbus = new DBus(this);
			this.hold();
		}

		/**
		 * First run: create and present main ({@link MainWindow} primes Shell roles).
		 * Later: remorph if needed, else Shell ``show('main')``.
		 */
		protected override void activate()
		{
			if (this.window == null) {
				this.window = new MainWindow(this);
				this.add_window(this.window);
				this.window.present();
				return;
			}
			if (!this.window.is_docked) {
				// Shell may have become ready after a reload — ensure enables if needed.
				this.window.shell.ensure(() => {
					if (!this.window.shell.is_ready) {
						return;
					}
					if (!this.window.is_docked) {
						this.window.show_docked();
					}
					GLib.debug("redock after remorph dock_mode=%d", (int) this.dbus.dock_mode);
					this.dbus.redock();
				});
				return;
			}
			this.dbus.call("show", new GLib.Variant("(s)", "main"));
			this.window.set_default_size(
				this.window.monitor_geo.width * this.window.config.width / 100,
				this.window.monitor_geo.height * this.window.config.height / 100
			);
			GLib.debug("redock activate docked dock_mode=%d", (int) this.dbus.dock_mode);
			this.dbus.redock();
		}

		protected override int command_line(GLib.ApplicationCommandLine command_line)
		{
			opt_debug = false;
			opt_debug_critical = false;
			opt_toggle = false;
			opt_quit = false;
			opt_toggle_key = "";

			string[] args = command_line.get_arguments();
			var opt_context = new GLib.OptionContext(this.get_application_id());
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(app_options, null);

			// --help must not reach OptionContext.parse: that exits(0) the primary
			// instance (kills the running app when invoked from a secondary CLI).
			foreach (var arg in args) {
				if (arg == "--help" || arg == "-h") {
					command_line.print("%s", opt_context.get_help(true, null));
					if (!command_line.is_remote) {
						this.quit();
					}
					return 0;
				}
			}

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

			if (opt_toggle_key != "") {
				try {
					var config = Config.load();
					config.key_toggle = opt_toggle_key;
					config.save();
					// Settings-only; no window required (no throwaway parent).
					new GnomeShell(this.window).ensure_toggle_binding(opt_toggle_key);
				} catch (GLib.Error e) {
					GLib.warning("toggle-key failed: %s", e.message);
				}
				if (!opt_toggle && !opt_quit) {
					return 0;
				}
			}

			if (opt_quit) {
				this.dbus.quit();
				return 0;
			}

			if (opt_toggle) {
				this.dbus.toggle();
				return 0;
			}

			this.activate();
			return 0;
		}
	}
}
