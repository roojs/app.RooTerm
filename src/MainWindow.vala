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
		private HostSearchPulldown host_search;
		private HostTree host_tree;
		private HostStack host_stack;
		private SessionController sessions;
		private AsbruConfig asbru_config;
		private Gtk.Paned paned;

		/**
		 * Builds the window: title, search pulldown, host tree, session stack.
		 *
		 * @param app Owning {@link Application}
		 */
		public MainWindow(Application app)
		{
			var config = new AsbruConfig();
			try {
				config.load();
			} catch (GLib.Error e) {
				GLib.warning("asbru config load failed: %s", e.message);
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

			this.asbru_config = config;

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

			this.host_search = new HostSearchPulldown(this.asbru_config) {
				halign = Gtk.Align.CENTER,
				hexpand = false
			};
			this.header_bar.set_title_widget(this.host_search);

			this.host_stack = new HostStack();
			this.sessions = new SessionController(this.host_stack);
			this.sessions.terminal_font = this.asbru_config.terminal_font;
			this.sessions.display_changed.connect(() => {
				this.title = this.sessions.display;
				if (this.sessions.display == "Roo Term") {
					this.host_search.placeholder_text = "Ctrl+Shift+O";
					return;
				}
				this.host_search.placeholder_text = this.sessions.display;
			});

			this.host_tree = new HostTree();
			this.host_tree.fill(this.asbru_config);
			this.host_tree.connection_activated.connect((conn) => {
				this.sessions.open(conn);
			});
			this.host_tree.connection_highlighted.connect((conn) => {
				var page = this.host_stack.pages.get_child_by_name(conn.uuid) as HostPage;
				if (page == null) {
					return;
				}
				this.host_stack.pages.visible_child = page;
				this.sessions.focus();
			});
			this.host_tree.terminal_selected.connect((conn, index) => {
				var page = this.host_stack.pages.get_child_by_name(conn.uuid) as HostPage;
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
				var page = this.host_stack.pages.get_child_by_name(conn.uuid) as HostPage;
				if (page == null || page.tab_view.n_pages == 0) {
					this.sessions.open(conn);
					return;
				}
				this.host_stack.pages.visible_child = page;
				page.tab_view.selected_page = page.tab_view.get_nth_page(0);
				this.sessions.focus();
				var term = page.tab_view.selected_page.child as SshTerminal;
				if (term == null) {
					return;
				}
				term.terminal.grab_focus();
			});

			var search_action = new GLib.SimpleAction("search", null);
			search_action.activate.connect(() => {
				this.host_search.grab_focus();
				this.host_search.entry.select_region(0, -1);
			});
			this.add_action(search_action);
			app.set_accels_for_action("win.search", { "<Control><Shift>o" });

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
