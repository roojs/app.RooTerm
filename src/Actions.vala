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
	 * ``win.*`` {@link GLib.SimpleAction}s and accelerators for
	 * {@link MainWindow}. Construct once and keep a field so the instance
	 * stays alive.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.actions = new Actions(this);
	 * }}}
	 */
	public class Actions : GLib.Object
	{
		private weak MainWindow window;

		/**
		 * Register all window actions and their accelerators on ``window``.
		 *
		 * @param window Owning main window
		 */
		public Actions(MainWindow window)
		{
			this.window = window;
			var app = (Application) window.application;

			var search_action = new GLib.SimpleAction("search", null);
			search_action.activate.connect(() => {
				this.window.host_search.grab_focus();
				this.window.host_search.entry.select_region(0, -1);
			});
			this.window.add_action(search_action);
			app.set_accels_for_action("win.search", { this.window.config.key_search });

			var new_term_action = new GLib.SimpleAction("new-terminal", null);
			new_term_action.activate.connect(() => {
				this.window.sessions.open_local(this.window.localhost);
			});
			this.window.add_action(new_term_action);
			app.set_accels_for_action("win.new-terminal", {
				this.window.config.key_new_terminal
			});

			var new_ssh_action = new GLib.SimpleAction("new-ssh", null);
			new_ssh_action.activate.connect(() => {
				var page = this.window.host_stack.pages.visible_child as Host.Page;
				if (page == null) {
					this.window.sessions.open_local(this.window.localhost);
					return;
				}
				var conn = page.connection;
				switch (conn.kind) {
					case Host.ConnectionKind.HOST:
					case Host.ConnectionKind.LXC:
						break;

					default:
						this.window.sessions.open_local(this.window.localhost);
						return;
				}
				var job = new Jobs.OpenSession(this.window, conn);
				GLib.Idle.add(() => {
					this.window.present();
					job.terminal.terminal.grab_focus();
					return false;
				});
				job.run.begin((obj, res) => {
					try {
						job.run.end(res);
					} catch (Jobs.Error e) {
						GLib.warning("open session failed name=%s: %s",
							conn.name, e.message);
					}
				});
			});
			this.window.add_action(new_ssh_action);
			app.set_accels_for_action("win.new-ssh", { this.window.config.key_new_ssh });

			var close_term_action = new GLib.SimpleAction("close-terminal", null);
			close_term_action.activate.connect(() => {
				this.window.sessions.close_current();
			});
			this.window.add_action(close_term_action);
			app.set_accels_for_action("win.close-terminal", {
				this.window.config.key_close_terminal
			});

			var prev_tab_action = new GLib.SimpleAction("prev-tab", null);
			prev_tab_action.activate.connect(() => {
				this.window.sessions.select_tab(-1);
			});
			this.window.add_action(prev_tab_action);
			app.set_accels_for_action("win.prev-tab", { this.window.config.key_prev_tab });

			var next_tab_action = new GLib.SimpleAction("next-tab", null);
			next_tab_action.activate.connect(() => {
				this.window.sessions.select_tab(1);
			});
			this.window.add_action(next_tab_action);
			app.set_accels_for_action("win.next-tab", { this.window.config.key_next_tab });

			var select_all_action = new GLib.SimpleAction("select-all", null);
			select_all_action.activate.connect(() => {
				this.window.sessions.select_all();
			});
			this.window.add_action(select_all_action);
			app.set_accels_for_action("win.select-all", {
				this.window.config.key_select_all
			});

			var copy_action = new GLib.SimpleAction("copy", null);
			copy_action.activate.connect(() => {
				var page = this.window.host_stack.pages.visible_child as Host.Page;
				if (page == null || page.current == null) {
					return;
				}
				page.current.terminal.copy_clipboard_format(Vte.Format.TEXT);
			});
			this.window.add_action(copy_action);
			app.set_accels_for_action("win.copy", { this.window.config.key_copy });

			var paste_action = new GLib.SimpleAction("paste", null);
			paste_action.activate.connect(() => {
				var page = this.window.host_stack.pages.visible_child as Host.Page;
				if (page == null || page.current == null) {
					return;
				}
				page.current.terminal.paste_clipboard();
			});
			this.window.add_action(paste_action);
			app.set_accels_for_action("win.paste", { this.window.config.key_paste });

			var reset_action = new GLib.SimpleAction("reset-terminal", null);
			reset_action.activate.connect(() => {
				var page = this.window.host_stack.pages.visible_child as Host.Page;
				if (page == null || page.current == null) {
					return;
				}
				page.current.terminal.reset(true, true);
			});
			this.window.add_action(reset_action);
			app.set_accels_for_action("win.reset-terminal", {
				this.window.config.key_reset_terminal
			});

			var toggle_action = new GLib.SimpleAction("toggle", null);
			toggle_action.activate.connect(() => {
				app.dbus.toggle();
			});
			this.window.add_action(toggle_action);
			// Shell / media-keys own the global binding; this covers in-app when focused.
			app.set_accels_for_action("win.toggle", { this.window.config.key_toggle });

			var fullscreen_action = new GLib.SimpleAction.stateful(
				"fullscreen",
				null,
				new GLib.Variant.boolean(false)
			);
			fullscreen_action.change_state.connect((value) => {
				fullscreen_action.set_state(value);
				this.window.fullscreen = value.get_boolean();
				this.window.dbus.fullscreen = this.window.fullscreen;
				this.window.host_stack.fullscreen(this.window.fullscreen);
				if (!this.window.is_docked) {
					return;
				}
				this.window.set_default_size(
					this.window.monitor_geo.width * this.window.config.width / 100,
					this.window.fullscreen
						? this.window.monitor_geo.height
						: this.window.monitor_geo.height * this.window.config.height / 100
				);
				this.window.dbus.redock();
			});
			fullscreen_action.activate.connect(() => {
				fullscreen_action.change_state(
					new GLib.Variant.boolean(!fullscreen_action.get_state().get_boolean())
				);
			});
			this.window.add_action(fullscreen_action);
			app.set_accels_for_action("win.fullscreen", {
				this.window.config.key_fullscreen
			});

			var prefs_action = new GLib.SimpleAction("preferences", null);
			prefs_action.activate.connect(() => {
				try {
					string[] argv = { "rooterm", "--preferences" };
					GLib.Process.spawn_async(
						null, argv, null, GLib.SpawnFlags.SEARCH_PATH, null, null
					);
				} catch (GLib.Error e) {
					GLib.warning("preferences: %s", e.message);
				}
			});
			this.window.add_action(prefs_action);
			app.set_accels_for_action("win.preferences", {
				this.window.config.key_preferences
			});

			var about_action = new GLib.SimpleAction("about", null);
			about_action.activate.connect(() => {
				this.window.dbus.about();
			});
			this.window.add_action(about_action);

			var quit_action = new GLib.SimpleAction("quit", null);
			quit_action.activate.connect(() => {
				this.window.dbus.quit();
			});
			this.window.add_action(quit_action);
			app.set_accels_for_action("win.quit", { this.window.config.key_quit });
		}
	}
}
