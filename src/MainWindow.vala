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
	 * Main window: header, host search, host tree, and host terminal stack.
	 * Window close closes the current terminal (then shows another if any).
	 */
	public class MainWindow : Adw.ApplicationWindow
	{
		private Adw.HeaderBar header_bar;
		public HostSearchPulldown host_search;
		public HostTree host_tree;
		private HostStack host_stack;
		public SessionController sessions;
		public Config config;
		private Gtk.Paned paned;

		/**
		 * Builds the window: title, search pulldown, host tree, session stack.
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

			Object(
				application: app,
				title: "Roo Term",
				icon_name: "org.roojs.rooterm",
				default_width: config.window_width,
				default_height: config.window_height
			);

			var css = new Gtk.CssProvider();
			css.load_from_resource("/rooterm/style.css");
			Gtk.StyleContext.add_provider_for_display(
				this.get_display(),
				css,
				Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
			);

			this.config = config;
			var localhost = new Connection() {
				uuid = "localhost",
				name = "Localhost",
				kind = ConnectionKind.LOCAL
			};
			this.config.tree.append(null, localhost);
			this.config.tree.sort((a, b) => {
				if (a.kind == ConnectionKind.LOCAL) {
					return -1;
				}
				if (b.kind == ConnectionKind.LOCAL) {
					return 1;
				}
				return a.name.collate(b.name);
			});
			GLib.Idle.add(() => {
				this.config.store_pending_secrets();
				return false;
			});

			this.header_bar = new Adw.HeaderBar();
			var logo = new Gtk.Image.from_icon_name("utilities-terminal-symbolic") {
				pixel_size = 20,
				valign = Gtk.Align.CENTER
			};
			var title_label = new Gtk.Label("Roo Term") {
				valign = Gtk.Align.CENTER
			};
			title_label.add_css_class("heading");
			var brand = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				valign = Gtk.Align.CENTER
			};
			brand.append(logo);
			brand.append(title_label);
			this.header_bar.pack_start(brand);

			this.host_search = new HostSearchPulldown(this.config) {
				halign = Gtk.Align.CENTER,
				hexpand = false
			};
			this.header_bar.set_title_widget(this.host_search);

			this.host_stack = new HostStack();
			this.sessions = new SessionController(this.host_stack, this.config.tree);
			this.sessions.terminal_font = this.config.terminal_font;
			this.sessions.display_changed.connect(() => {
				this.title = this.sessions.display;
				if (this.sessions.display == "Roo Term") {
					this.host_search.placeholder_text = "Ctrl+Shift+O";
					return;
				}
				this.host_search.placeholder_text = this.sessions.display;
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
					var dlg = new ConnDialog(this);
					dlg.fill(conn, null);
					dlg.saved.connect((c) => {
						try {
							this.config.save();
						} catch (GLib.Error e) {
							GLib.warning("config save failed: %s", e.message);
						}
					});
					dlg.present(this);
				});
				alert.present(this);
			});

			this.host_tree = new HostTree(this);
			this.host_tree.connection_activated.connect((conn) => {
				if (conn.kind == ConnectionKind.LOCAL) {
					this.sessions.open_local(conn);
					return;
				}
				if (conn.kind == ConnectionKind.LOCAL_PATH) {
					this.sessions.open_local(conn.parent, conn.name);
					return;
				}
				this.sessions.open(conn);
			});
			this.host_tree.connection_highlighted.connect((conn) => {
				if (conn.kind == ConnectionKind.LOCAL_PATH) {
					var local_page = this.host_stack.pages.get_child_by_name(conn.parent.uuid) as HostPage;
					if (local_page == null || conn.local_tab < 0
							|| conn.local_tab >= local_page.tab_view.n_pages) {
						return;
					}
					this.host_stack.pages.visible_child = local_page;
					local_page.tab_view.selected_page = local_page.tab_view.get_nth_page(conn.local_tab);
					this.sessions.focus();
					return;
				}
				var page = this.host_stack.pages.get_child_by_name(conn.uuid) as HostPage;
				if (page == null) {
					return;
				}
				this.host_stack.pages.visible_child = page;
				this.sessions.focus();
			});
			this.host_tree.terminal_selected.connect((conn, index) => {
				if (conn.kind == ConnectionKind.LOCAL_PATH) {
					var local_page = this.host_stack.pages.get_child_by_name(conn.parent.uuid) as HostPage;
					if (local_page == null || conn.local_tab < 0
							|| conn.local_tab >= local_page.tab_view.n_pages) {
						return;
					}
					this.host_tree.select(conn);
					this.host_stack.pages.visible_child = local_page;
					local_page.tab_view.selected_page = local_page.tab_view.get_nth_page(conn.local_tab);
					this.sessions.focus();
					return;
				}
				var page = this.host_stack.pages.get_child_by_name(conn.uuid) as HostPage;
				if (page == null || index < 0 || index >= page.tab_view.n_pages) {
					return;
				}
				this.host_tree.select(conn);
				this.host_stack.pages.visible_child = page;
				page.tab_view.selected_page = page.tab_view.get_nth_page(index);
				this.sessions.focus();
			});
			this.host_tree.add_connection.connect((group) => {
				var dlg = new ConnDialog(this);
				dlg.fill(null, group);
				dlg.saved.connect((conn) => {
					this.config.by_uuid.set(conn.uuid, conn);
					this.config.tree.append(group, conn);
					try {
						this.config.save();
					} catch (GLib.Error e) {
						GLib.warning("config save failed: %s", e.message);
					}
				});
				dlg.present(this);
			});
			this.host_tree.edit_connection.connect((host) => {
				var dlg = new ConnDialog(this);
				dlg.fill(host, null);
				dlg.saved.connect((conn) => {
					try {
						this.config.save();
					} catch (GLib.Error e) {
						GLib.warning("config save failed: %s", e.message);
					}
				});
				dlg.present(this);
			});
			this.host_tree.delete_connection.connect((conn) => {
				var alert = new Adw.AlertDialog("Delete " + conn.name + "?", null);
				alert.add_response("cancel", "Cancel");
				alert.add_response("delete", "Delete");
				alert.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);
				alert.default_response = "cancel";
				alert.close_response = "cancel";
				alert.response.connect((response) => {
					if (response != "delete") {
						return;
					}
					conn.deleted = true;
					this.config.tree.remove(conn);
					try {
						this.config.save();
					} catch (GLib.Error e) {
						GLib.warning("config save failed: %s", e.message);
					}
				});
				alert.present(this);
			});
			this.host_tree.new_local.connect((conn) => {
				if (conn.kind == ConnectionKind.LOCAL_PATH) {
					this.sessions.open_local(conn.parent, conn.name);
					return;
				}
				this.sessions.open_local(conn);
			});
			this.host_tree.close_local.connect((conn) => {
				if (conn.parent == null || conn.local_tab < 0) {
					return;
				}
				var page = this.host_stack.pages.get_child_by_name(conn.parent.uuid) as HostPage;
				if (page == null || conn.local_tab >= page.tab_view.n_pages) {
					return;
				}
				page.tab_view.close_page(page.tab_view.get_nth_page(conn.local_tab));
				this.sessions.focus();
			});
			this.host_search.connection_selected.connect((conn) => {
				this.host_tree.select(conn);
				if (conn.kind == ConnectionKind.LOCAL_PATH) {
					if (conn.parent == null) {
						return;
					}
					var local_page = this.host_stack.pages.get_child_by_name(conn.parent.uuid) as HostPage;
					if (local_page == null || conn.local_tab < 0
							|| conn.local_tab >= local_page.tab_view.n_pages) {
						return;
					}
					this.host_stack.pages.visible_child = local_page;
					local_page.tab_view.selected_page = local_page.tab_view.get_nth_page(conn.local_tab);
					this.sessions.focus();
					((Terminal) local_page.tab_view.selected_page.child).terminal.grab_focus();
					return;
				}
				var page = this.host_stack.pages.get_child_by_name(conn.uuid) as HostPage;
				if (page == null || page.tab_view.n_pages == 0) {
					if (conn.kind == ConnectionKind.LOCAL) {
						this.sessions.open_local(conn);
						return;
					}
					this.sessions.open(conn);
					return;
				}
				this.host_stack.pages.visible_child = page;
				page.tab_view.selected_page = page.tab_view.get_nth_page(0);
				this.sessions.focus();
				((Terminal) page.tab_view.selected_page.child).terminal.grab_focus();
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
				this.sessions.open_new(localhost);
			});
			this.add_action(new_term_action);
			app.set_accels_for_action("win.new-terminal", { "<Control><Shift>t" });

			var tree_pos = (int) (config.window_width * 0.30);
			this.paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
				start_child = this.host_tree,
				end_child = this.host_stack,
				resize_start_child = false,
				shrink_start_child = true,
				position = tree_pos,
				hexpand = true,
				vexpand = true
			};

			var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			content.append(this.header_bar);
			content.append(this.paned);
			this.content = content;

			this.close_request.connect(() => {
				if (this.sessions.close_current()) {
					return true;
				}
				return false;
			});
		}

		public override void size_allocate(int width, int height, int baseline)
		{
			base.size_allocate(width, height, baseline);
			if (this.host_search == null) {
				return;
			}
			this.host_search.width_request = (int) (width * 0.50);
		}
	}
}
