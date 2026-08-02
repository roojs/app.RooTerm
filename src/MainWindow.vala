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
	 * Host tree + search on the left, terminal stack on the right.
	 *
	 * When {@link is_docked}: undecorated Guake-style drop-down; Shell docks
	 * under the top panel; close closes the current terminal (or hides).
	 * Otherwise: decorated 960×640 setup chrome; window close quits the app.
	 */
	public class MainWindow : Gtk.ApplicationWindow
	{
		public Host.SearchPulldown host_search;
		public Host.Tree host_tree;
		public Host.Stack host_stack;
		public Session.Controller sessions;
		public Config config;
		public Host.Connection localhost;
		/**
		 * Primary monitor geometry (Shell docks; size percents use this).
		 */
		public Gdk.Rectangle monitor_geo;
		/**
		 * True when undecorated drop-down (Shell extension enabled).
		 * False when decorated setup window (960×640).
		 */
		public bool is_docked = false;
		/**
		 * True while a {@link GnomeShell} setup/restart dialog is open.
		 * {@link DBus.toggle} must not hide/show the window then.
		 */
		public bool block_toggle = false;
		/**
		 * Shared add/edit connection window (Shell Show/Hide).
		 */
		public Dialog.Connection connection_editor;
		/**
		 * Shared preferences window (Shell Show/Hide).
		 */
		public Dialog.Preferences preferences_editor;
		/**
		 * Extension install / readiness / window {@link GnomeShell.register}.
		 */
		public GnomeShell shell;
		/**
		 * Session-bus {@link DBus} on the owning {@link Application}.
		 */
		public DBus dbus {
			get {
				return ((Application) this.application).dbus;
			}
		}

		/**
		 * Switch to underbar drop-down chrome and set {@link DBus.dock_mode}.
		 * Call when Shell is ready and the window is still in normal mode.
		 */
		public void show_docked()
		{
			this.is_docked = true;
			this.dbus.dock_mode = true;
			GLib.debug(
				"show_docked size=%dx%d dock_mode=1",
				this.monitor_geo.width * this.config.width / 100,
				this.monitor_geo.height * this.config.height / 100
			);
			this.decorated = false;
			this.resizable = false;
			this.add_css_class("drop-down");
			this.set_default_size(
				this.monitor_geo.width * this.config.width / 100,
				this.monitor_geo.height * this.config.height / 100
			);
		}

		/**
		 * Builds the window: title, search pulldown, host tree, session stack.
		 * Chooses docked vs normal chrome from Shell extension state.
		 *
		 * @param app Owning {@link Application}
		 */
		public MainWindow(Application app)
		{
			Config config;
			try {
				config = Config.load();
			} catch (GLib.Error e) {
				GLib.warning("config load failed: %s", e.message);
				config = new Config();
			}

			var monitors = Gdk.Display.get_default().get_monitors();
			var geo = Gdk.Rectangle() { width = 1280, height = 800 };
			if (monitors.get_n_items() > 0) {
				geo = ((Gdk.Monitor) monitors.get_item(0)).geometry;
			}

			Object(
				application: app,
				title: "Roo Term",
				icon_name: "org.roojs.rooterm",
				decorated: true,
				resizable: true,
				default_width: 960,
				default_height: 640
			);
			this.monitor_geo = geo;
			this.config = config;
			this.shell = new GnomeShell(this);
			this.connection_editor = new Dialog.Connection(this);
			this.preferences_editor = new Dialog.Preferences(this);
			this.map.connect(() => {
				this.shell.register(this, "main");
			});
			GLib.Bus.watch_name(
				GLib.BusType.SESSION,
				"org.roojs.RooTerm.Shell",
				GLib.BusNameWatcherFlags.NONE,
				() => {
					this.shell.register(this, "main");
					this.shell.register(this.preferences_editor, "preferences");
					this.shell.register(this.connection_editor, "connection");
				},
				() => {
				}
			);
			this.config.notify["height"].connect(() => {
				if (!this.is_docked) {
					return;
				}
				this.set_default_size(
					this.monitor_geo.width * this.config.width / 100,
					this.monitor_geo.height * this.config.height / 100
				);
				this.dbus.redock();
			});
			this.config.notify["width"].connect(() => {
				if (!this.is_docked) {
					return;
				}
				this.set_default_size(
					this.monitor_geo.width * this.config.width / 100,
					this.monitor_geo.height * this.config.height / 100
				);
				this.dbus.redock();
			});
			this.config.notify["placement"].connect(() => {
				if (!this.is_docked) {
					return;
				}
				this.dbus.redock();
			});
			if (this.shell.is_ready) {
				this.show_docked();
			}
			var css = new Gtk.CssProvider();
			css.load_from_resource("/style.css");
			Gtk.StyleContext.add_provider_for_display(
				this.get_display(),
				css,
				Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
			);
			this.localhost = new Host.Connection() {
				uuid = "localhost",
				name = "Localhost",
				kind = Host.ConnectionKind.LOCAL
			};
			this.config.tree.append(null, this.localhost);
			this.config.tree.sort((a, b) => {
				if (a.kind == Host.ConnectionKind.LOCAL) {
					return -1;
				}
				if (b.kind == Host.ConnectionKind.LOCAL) {
					return 1;
				}
				return a.name.collate(b.name);
			});
			GLib.Idle.add(() => {
				this.config.store_pending_secrets();
				return false;
			});

			this.host_search = new Host.SearchPulldown(this.config) {
				halign = Gtk.Align.FILL,
				hexpand = true,
				vexpand = false,
				margin_start = 6,
				margin_end = 4,
				margin_top = 4,
				margin_bottom = 6,
				placeholder_text = "Ctrl+Shift+O — search hosts"
			};

			this.host_stack = new Host.Stack();
			this.sessions = new Session.Controller(this.host_stack, this.config.tree, this.config);
			this.sessions.terminal_font = this.config.terminal_font;
			this.sessions.display_changed.connect(() => {
				this.title = this.sessions.display;
				var page = this.host_stack.pages.visible_child as Host.Page;
				if (page != null && page.current != null) {
					this.host_tree.select(page.current.connection);
				}
			});
			this.sessions.sudo_password_failed.connect((conn) => {
				var alert = new Adw.AlertDialog(
					"Password failed",
					"The sudo password for " + conn.name + " was rejected. Edit the connection to fix it."
				);
				alert.add_response("ok", "OK");
				alert.add_response("edit", "Edit");
				alert.default_response = "edit";
				alert.close_response = "ok";
				alert.response.connect((response) => {
					if (response != "edit") {
						return;
					}
					this.connection_editor.fill(conn, null);
					this.dbus.call("Show", new GLib.Variant("(s)", "connection"));
				});
				alert.present(this);
			});

			this.host_tree = new Host.Tree(this);
			this.host_tree.connection_activated.connect((conn) => {
				if (conn.kind == Host.ConnectionKind.LOCAL) {
					this.sessions.open_local(conn);
					return;
				}
				if (conn.kind == Host.ConnectionKind.LOCAL_PATH) {
					var path_term = (Terminal.Base) conn.sessions.get_item(0);
					this.sessions.open_local(conn.parent, path_term.cwd);
					return;
				}
				var job = new Jobs.OpenSession(this, conn);
				GLib.Idle.add(() => {
					this.present();
					job.terminal.terminal.grab_focus();
					return false;
				});
				job.run.begin((obj, res) => {
					try {
						job.run.end(res);
					} catch (Jobs.Error e) {
						GLib.warning("open session failed name=%s: %s", conn.name, e.message);
					}
				});
			});
			this.host_tree.connection_highlighted.connect((conn) => {
				if (conn.kind == Host.ConnectionKind.LOCAL_PATH) {
					var term = (Terminal.Base) conn.sessions.get_item(0);
					var local_page = this.host_stack.pages.get_child_by_name(conn.parent.uuid) as Host.Page;
					if (local_page == null) {
						return;
					}
					this.host_stack.pages.visible_child = local_page;
					local_page.tab_view.selected_page = local_page.tab_view.get_page(term);
					this.sessions.focus();
					return;
				}
				var page = this.host_stack.pages.get_child_by_name(conn.uuid) as Host.Page;
				if (page == null) {
					return;
				}
				this.host_stack.pages.visible_child = page;
				this.sessions.focus();
			});
			this.host_tree.terminal_selected.connect((conn, index) => {
				if (conn.kind == Host.ConnectionKind.LOCAL_PATH) {
					var term = (Terminal.Base) conn.sessions.get_item(0);
					var local_page = this.host_stack.pages.get_child_by_name(conn.parent.uuid) as Host.Page;
					if (local_page == null) {
						return;
					}
					this.host_tree.select(conn);
					this.host_stack.pages.visible_child = local_page;
					local_page.tab_view.selected_page = local_page.tab_view.get_page(term);
					this.sessions.focus();
					return;
				}
				var page = this.host_stack.pages.get_child_by_name(conn.uuid) as Host.Page;
				if (page == null || index < 0 || index >= page.tab_view.n_pages) {
					return;
				}
				this.host_tree.select(conn);
				this.host_stack.pages.visible_child = page;
				page.tab_view.selected_page = page.tab_view.get_nth_page(index);
				this.sessions.focus();
			});
			this.host_search.connection_selected.connect((conn) => {
				this.host_tree.select(conn);
				if (conn.kind == Host.ConnectionKind.LOCAL_PATH) {
					var term = (Terminal.Base) conn.sessions.get_item(0);
					var local_page = this.host_stack.pages.get_child_by_name(conn.parent.uuid) as Host.Page;
					if (local_page == null) {
						return;
					}
					this.host_stack.pages.visible_child = local_page;
					local_page.tab_view.selected_page = local_page.tab_view.get_page(term);
					this.sessions.focus();
					term.terminal.grab_focus();
					return;
				}
				var page = this.host_stack.pages.get_child_by_name(conn.uuid) as Host.Page;
				if (page == null || page.tab_view.n_pages == 0) {
					if (conn.kind == Host.ConnectionKind.LOCAL) {
						this.sessions.open_local(conn);
						return;
					}
					var job = new Jobs.OpenSession(this, conn);
					GLib.Idle.add(() => {
						this.present();
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
					return;
				}
				this.host_stack.pages.visible_child = page;
				page.tab_view.selected_page = page.tab_view.get_nth_page(0);
				this.sessions.focus();
				((Terminal.Base) page.tab_view.selected_page.child).terminal.grab_focus();
			});

			var search_action = new GLib.SimpleAction("search", null);
			search_action.activate.connect(() => {
				this.host_search.grab_focus();
				this.host_search.entry.select_region(0, -1);
			});
			this.add_action(search_action);
			app.set_accels_for_action("win.search", { "<Control><Shift>o" });

			var new_term_action = new GLib.SimpleAction("new-terminal", null);
			new_term_action.activate.connect(() => {
				this.sessions.open_new(this.localhost, this);
			});
			this.add_action(new_term_action);
			app.set_accels_for_action("win.new-terminal", { "<Control><Shift>t" });

			var close_term_action = new GLib.SimpleAction("close-terminal", null);
			close_term_action.activate.connect(() => {
				this.sessions.close_current();
			});
			this.add_action(close_term_action);
			app.set_accels_for_action("win.close-terminal", { "<Control><Shift>w" });

			var prev_tab_action = new GLib.SimpleAction("prev-tab", null);
			prev_tab_action.activate.connect(() => {
				this.sessions.select_tab(-1);
			});
			this.add_action(prev_tab_action);
			app.set_accels_for_action("win.prev-tab", { "<Control><Shift>Left" });

			var next_tab_action = new GLib.SimpleAction("next-tab", null);
			next_tab_action.activate.connect(() => {
				this.sessions.select_tab(1);
			});
			this.add_action(next_tab_action);
			app.set_accels_for_action("win.next-tab", { "<Control><Shift>Right" });

			var select_all_action = new GLib.SimpleAction("select-all", null);
			select_all_action.activate.connect(() => {
				this.sessions.select_all();
			});
			this.add_action(select_all_action);
			app.set_accels_for_action("win.select-all", { "<Control><Shift>a" });

			var toggle_action = new GLib.SimpleAction("toggle", null);
			toggle_action.activate.connect(() => {
				app.dbus.toggle();
			});
			this.add_action(toggle_action);
			// Shell / media-keys own the global binding; this covers in-app when focused.
			app.set_accels_for_action("win.toggle", { this.config.toggle_key });

			var prefs_action = new GLib.SimpleAction("preferences", null);
			prefs_action.activate.connect(() => {
				this.preferences_editor.fill();
				this.dbus.call("Show", new GLib.Variant("(s)", "preferences"));
			});
			this.add_action(prefs_action);
			app.set_accels_for_action("win.preferences", { "<Control>comma" });

			var tree_width = 300;
			this.host_tree.add_css_class("host-tree");
			this.host_tree.vexpand = true;
			this.host_tree.hexpand = true;

			// Left: tree scrolls; search pinned under it. Right: VTE + tabs (Host.Page).
			var left = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = false,
				vexpand = true,
				width_request = tree_width
			};
			left.add_css_class("host-pane");
			left.append(this.host_tree);
			left.append(this.host_search);

			var paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
				start_child = left,
				end_child = this.host_stack,
				resize_start_child = false,
				shrink_start_child = false,
				position = tree_width,
				hexpand = true,
				vexpand = true
			};

			var shadow = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = false,
				height_request = 14,
				can_target = false
			};
			shadow.add_css_class("drop-shadow");

			var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			root.append(paned);
			root.append(shadow);
			this.child = root;

			this.map.connect(() => {
				if (!this.is_docked) {
					return;
				}
				this.set_default_size(
					this.monitor_geo.width * this.config.width / 100,
					this.monitor_geo.height * this.config.height / 100
				);
			});

			this.close_request.connect(() => {
				if (!this.is_docked) {
					((Application) this.application).quit();
					return true;
				}
				if (this.sessions.close_current()) {
					return true;
				}
				this.dbus.call("Hide", new GLib.Variant("(s)", "main"));
				return true;
			});

			var term = this.sessions.open_local(this.localhost);
			// After Application add_window + present: focus, prime Shell roles, dock cue.
			GLib.Idle.add(() => {
				this.host_tree.select(term.connection);
				this.sessions.focus();
				this.preferences_editor.present();
				this.connection_editor.present();
				GLib.Timeout.add(400, () => {
					this.dbus.call("Hide", new GLib.Variant("(s)", "preferences"));
					this.dbus.call("Hide", new GLib.Variant("(s)", "connection"));
					return GLib.Source.REMOVE;
				});
				this.shell.ensure(() => {
					if (!this.shell.is_ready) {
						return;
					}
					if (!this.is_docked) {
						this.show_docked();
					}
					GLib.debug("redock after ensure dock_mode=%d",
						(int) this.dbus.dock_mode);
					this.dbus.redock();
				});
				return false;
			});
		}
	}
}
