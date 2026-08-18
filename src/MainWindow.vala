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
	public class MainWindow : Gtk.ApplicationWindow, ShellInterface
	{
		/**
		 * Host-tree name filter. Bound to {@link Host.Tree.search}.
		 */
		public Gtk.SearchEntry host_search;
		public Host.Tree host_tree;
		public Host.Stack host_stack;
		public Session.Controller sessions;
		/**
		 * One VTE right-click menu for all tabs (reparents per click).
		 */
		public Terminal.ContextMenu terminal_menu;
		/**
		 * ``win.*`` actions (kept alive for refcounting).
		 */
		public Actions actions;
		public Config config;
		/**
		 * Nested host tree + flat search index (not on {@link Config}).
		 */
		public Host.TreeNodes tree {
			get;
			set;
			default = new Host.TreeNodes();
		}
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
		 * True while main fills the monitor work area (tab strip on top).
		 * Session runtime only — not saved; hide/show keeps it until the user exits.
		 */
		public bool fullscreen = false;
		/**
		 * True while a {@link GnomeShell} setup/restart dialog is open.
		 * {@link DBus.toggle} must not hide/show the window then.
		 */
		public bool block_toggle { get; set; default = false; }
		/**
		 * Active GNOME workspace index (0-based). Set by {@link DBus.workspace}.
		 */
		public int workspace = 0;
		/**
		 * True when Shell has been asked to hide the overlay (F1 / close).
		 * Restore runs when this is true and we are about to show.
		 */
		public bool hidden = false;
		/**
		 * Shared add/edit connection window (transient of main; GTK show/hide).
		 */
		public Dialog.Connection connection_editor;
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
				this.fullscreen
					? this.monitor_geo.width
					: this.monitor_geo.width * this.config.width / 100,
				this.fullscreen
					? this.monitor_geo.height
					: this.monitor_geo.height * this.config.height / 100
			);
			this.decorated = false;
			this.resizable = false;
			this.add_css_class("drop-down");
			this.set_default_size(
				this.fullscreen
					? this.monitor_geo.width
					: this.monitor_geo.width * this.config.width / 100,
				this.fullscreen
					? this.monitor_geo.height
					: this.monitor_geo.height * this.config.height / 100
			);
		}

		/**
		 * Select the last tab for {@link workspace} when the overlay shows.
		 * No-op if the pref is off, nothing is stored, or that tab is not open.
		 */
		public void restore()
		{
			if (!this.config.remember_workspace_tab) {
				return;
			}
			if (!this.config.workspace_tabs.has_key(this.workspace)) {
				return;
			}
			var conn = this.config.workspace_tabs.get(this.workspace);
			if (conn.sessions.get_n_items() == 0) {
				return;
			}
			var term = (Terminal.Base) conn.sessions.get_item(0);
			var name = conn.uuid;
			if (conn.kind == Host.ConnectionKind.LOCAL_PATH) {
				name = conn.parent.uuid;
			}
			var page = this.host_stack.pages.get_child_by_name(name) as Host.Page;
			if (page == null) {
				return;
			}
			this.host_stack.pages.visible_child = page;
			page.tab_view.selected_page = page.tab_view.get_page(term);
			this.sessions.focus();
		}

		/**
		 * Builds the window: title, search pulldown, host tree, session stack.
		 * Chooses docked vs normal chrome from Shell extension state.
		 *
		 * @param app Owning {@link Application}
		 */
		/**
		 * Builds the window: title, search pulldown, host tree, session stack.
		 * Chooses docked vs normal chrome from Shell extension state.
		 *
		 * @param app Owning {@link Application}
		 */
		public MainWindow(Application app)
		{
			var connections_path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "rooterm", "connections.json"
			);
			var first_run = !GLib.FileUtils.test(connections_path, GLib.FileTest.IS_REGULAR);

			Asbru.Config? asbru = new Asbru.Config();
			if (!first_run || !asbru.exists()) {
				asbru = null;
			} else {
				asbru.load();
			}

			var config = asbru != null ? asbru.to_config() : Config.load();

			var monitors = Gdk.Display.get_default().get_monitors();
			var geo = Gdk.Rectangle() { width = 1280, height = 800 };
			if (monitors.get_n_items() > 0) {
				geo = ((Gdk.Monitor) monitors.get_item(0)).geometry;
				for (var i = 1; i < monitors.get_n_items(); i++) {
					var g = ((Gdk.Monitor) monitors.get_item(i)).geometry;
					if (g.width * g.height <= geo.width * geo.height) {
						continue;
					}
					geo = g;
				}
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
			if (asbru != null) {
				this.tree = asbru.to_host_tree();
				this.tree.config = this.config;
				this.config.save();
				this.tree.save();
			} else {
				this.tree = Host.TreeNodes.load(this.config);
			}
			foreach (var index in this.config.workspace_uuids.keys) {
				var uuid = this.config.workspace_uuids.get(index);
				if (!this.tree.by_uuid.has_key(uuid)) {
					continue;
				}
				this.config.workspace_tabs.set(index, this.tree.by_uuid.get(uuid));
			}
			this.shell = new GnomeShell(this);
			this.connection_editor = new Dialog.Connection(this);
			this.map.connect(() => {
				this.shell.register(this, "main");
			});
			GLib.Bus.watch_name(
				GLib.BusType.SESSION,
				"org.roojs.RooTerm.Shell",
				GLib.BusNameWatcherFlags.NONE,
				() => {
					this.shell.register(this, "main");
				},
				() => {
				}
			);
			this.config.connect(this);
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
			if (!this.tree.by_uuid.has_key("localhost")) {
				this.tree.append(null, new Host.Connection() {
					uuid = "localhost",
					name = "Localhost",
					kind = Host.ConnectionKind.LOCAL
				});
				this.tree.save();
			}
			this.localhost = this.tree.by_uuid.get("localhost");
			var has_group = false;
			foreach (var conn in this.tree.by_uuid.values) {
				if (!conn.deleted && conn.kind == Host.ConnectionKind.GROUP) {
					has_group = true;
					break;
				}
			}
			if (!has_group) {
				var all = new Host.Connection() {
					uuid = GLib.Uuid.string_random(),
					name = "All",
					kind = Host.ConnectionKind.GROUP
				};
				this.tree.append(null, all);
				this.tree.save();
			}
			this.tree.sort((a, b) => {
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

			this.host_search = new Gtk.SearchEntry() {
				halign = Gtk.Align.FILL,
				hexpand = true,
				vexpand = false,
				margin_start = 6,
				margin_end = 0,
				margin_top = 4,
				margin_bottom = 6,
				placeholder_text = "Ctrl+Shift+O — search hosts",
				tooltip_text = "Ctrl+Shift+O"
			};

			this.host_stack = new Host.Stack();
			this.terminal_menu = new Terminal.ContextMenu(this);
			this.sessions = new Session.Controller(
				this.host_stack, this.tree, this.config, this.localhost
			);
			this.sessions.display_changed.connect(() => {
				this.title = this.sessions.display;
				var page = this.host_stack.pages.visible_child as Host.Page;
				if (page == null || page.current == null) {
					return;
				}
				this.host_tree.select(page.current.connection);
				if (!this.config.remember_workspace_tab) {
					return;
				}
				this.config.workspace_tabs.set(this.workspace, page.current.connection);
				this.config.workspace_uuids.set(this.workspace, page.current.connection.uuid);
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
					this.connection_editor.present();
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
			this.host_search.bind_property("text", this.host_tree, "search",
				GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE);

			this.actions = new Actions(this);

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
			var all_btn = new Gtk.ToggleButton() {
				icon_name = "view-list-symbolic",
				tooltip_text = "Show all hosts",
				valign = Gtk.Align.CENTER,
				margin_end = 4,
				margin_top = 4,
				margin_bottom = 6
			};
			all_btn.add_css_class("flat");
			all_btn.bind_property("active", this.host_tree, "show-all",
				GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE);
			var search_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = false
			};
			search_row.append(this.host_search);
			search_row.append(all_btn);
			left.append(search_row);

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
					this.fullscreen
						? this.monitor_geo.width
						: this.monitor_geo.width * this.config.width / 100,
					this.fullscreen
						? this.monitor_geo.height
						: this.monitor_geo.height * this.config.height / 100
				);
			});

			this.close_request.connect(() => {
				if (!this.is_docked) {
					if (this.dbus.quitting) {
						return false;
					}
					this.dbus.quit();
					return true;
				}
				if (this.sessions.close_current()) {
					return true;
				}
				this.terminal_menu.popdown();
				if (this.config.remember_workspace_tab) {
					this.config.save();
				}
				this.hidden = true;
				this.dbus.call_shell("hide", new GLib.Variant("(s)", "main"));
				return true;
			});

			var term = (Terminal.Local?) null;
			for (var i = 0; i < this.localhost.children.size; ) {
				var conn = this.localhost.children.get(i);
				if (conn.kind != Host.ConnectionKind.LOCAL_PATH) {
					i++;
					continue;
				}
				if (!GLib.FileUtils.test(conn.cwd, GLib.FileTest.IS_DIR)) {
					this.tree.remove(conn);
					continue;
				}
				term = this.sessions.open_local(conn);
				i++;
			}
			if (term == null) {
				term = this.sessions.open_local(this.localhost);
			}
			this.tree.save();
			// After Application add_window + present: focus + dock cue.
			GLib.Idle.add(() => {
				this.host_tree.select(term.connection);
				this.sessions.focus();
				this.shell.ensure(() => {
					if (!this.shell.is_ready) {
						return;
					}
					if (!this.is_docked) {
						this.show_docked();
					}
					GLib.debug("redock after ensure dock_mode=%d",
						(int) this.dbus.dock_mode);
					this.dbus.redock(this.fullscreen);
				});
				return false;
			});
		}
	}
}
