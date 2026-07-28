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
	 * Ásbrú host/group tree (single-click selects; double-click reserved for open).
	 * One terminal icon per open tab; active tab icon is green and clickable.
	 */
	public class HostTree : Gtk.Box
	{
		private Gtk.ListView list_view;
		public Gtk.SingleSelection selection;
		private Gtk.TreeListModel tree_model;
		private weak MainWindow window;

		/**
		 * Emitted on double-click / activate of a non-group connection.
		 */
		public signal void connection_activated(Connection connection);

		/**
		 * Emitted when a non-group connection is highlighted (single-click).
		 */
		public signal void connection_highlighted(Connection connection);

		/**
		 * Emitted when a per-tab terminal icon is clicked.
		 *
		 * @param connection Host for the icon
		 * @param tab_index Zero-based tab index to focus
		 */
		public signal void terminal_selected(Connection connection, int tab_index);

		/**
		 * Emitted for group context menu **Add connection**.
		 *
		 * @param group Parent group for the new host
		 */
		public signal void add_connection(Connection group);

		/**
		 * Emitted for host context menu **Edit connection**.
		 *
		 * @param host Host to edit
		 */
		public signal void edit_connection(Connection host);

		/**
		 * Emitted for host context menu **Delete** (after the user picks the item; confirm in window).
		 *
		 * @param connection Host or group to soft-delete
		 */
		public signal void delete_connection(Connection connection);

		/**
		 * Highlight ``connection`` in the tree (no spawn).
		 *
		 * @param connection Host to select (same instance as in the config tree)
		 */
		public void select(Connection connection)
		{
			for (var i = 0; i < this.tree_model.get_n_items(); i++) {
				var row = this.tree_model.get_item(i) as Gtk.TreeListRow;
				if (row == null || row.item != connection) {
					continue;
				}
				this.selection.selected = i;
				this.list_view.scroll_to(i, Gtk.ListScrollFlags.NONE, null);
				return;
			}
		}

		/**
		 * Build tree UI bound to ``config.tree`` (live root {@link HostTreeNodes}).
		 *
		 * @param window Main window (sessions / config for LXC refresh)
		 */
		public HostTree(MainWindow window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				hexpand: false,
				vexpand: true
			);
			this.window = window;

			this.tree_model = new Gtk.TreeListModel(
				window.config.tree,
				false,
				true,
				(item) => {
					var conn = item as Connection;
					if (conn == null) {
						return null;
					}
					return conn.children;
				}
			);

			this.selection = new Gtk.SingleSelection(this.tree_model) {
				autoselect = false,
				can_unselect = true
			};
			this.selection.notify["selected"].connect(() => {
				var row = this.selection.selected_item as Gtk.TreeListRow;
				var conn = row != null ? row.item as Connection : null;
				if (conn == null || conn.is_group) {
					return;
				}
				this.connection_highlighted(conn);
			});

			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var type_icon = new Gtk.Image() {
					pixel_size = 16,
					valign = Gtk.Align.CENTER
				};
				var name_label = new Gtk.Label("") {
					xalign = 0.0f,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END
				};
				var mark_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
					halign = Gtk.Align.END,
					valign = Gtk.Align.CENTER
				};
				var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
				row_box.append(type_icon);
				row_box.append(name_label);
				row_box.append(mark_box);
				var menu_click = new Gtk.GestureClick() {
					button = Gdk.BUTTON_SECONDARY
				};
				menu_click.pressed.connect((n_press, x, y) => {
					var menu_conn = row_box.get_data<Connection>("menu-conn");
					if (menu_conn == null || menu_conn.is_local || menu_conn.local_path) {
						return;
					}
					var pop = new Gtk.Popover();
					var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
					if (menu_conn.is_group) {
						var add_item = new Gtk.Button.with_label("Add connection") {
							has_frame = false,
							halign = Gtk.Align.FILL
						};
						add_item.clicked.connect(() => {
							pop.popdown();
							this.add_connection(menu_conn);
						});
						box.append(add_item);
						var can_delete = true;
						foreach (var child in menu_conn.children) {
							if (!child.deleted) {
								can_delete = false;
								break;
							}
						}
						var del_item = new Gtk.Button.with_label("Delete") {
							has_frame = false,
							halign = Gtk.Align.FILL,
							sensitive = can_delete
						};
						del_item.clicked.connect(() => {
							pop.popdown();
							this.delete_connection(menu_conn);
						});
						box.append(del_item);
					} else {
						var edit_item = new Gtk.Button.with_label("Edit connection") {
							has_frame = false,
							halign = Gtk.Align.FILL
						};
						edit_item.clicked.connect(() => {
							pop.popdown();
							this.edit_connection(menu_conn);
						});
						box.append(edit_item);
						if (menu_conn.lxc_host && !menu_conn.lxc_container) {
							var refresh_item = new Gtk.Button.with_label("Refresh containers") {
								has_frame = false,
								halign = Gtk.Align.FILL
							};
							refresh_item.clicked.connect(() => {
								pop.popdown();
								menu_conn.refresh_containers(this.window);
							});
							box.append(refresh_item);
						}
						var del_item = new Gtk.Button.with_label("Delete") {
							has_frame = false,
							halign = Gtk.Align.FILL
						};
						del_item.clicked.connect(() => {
							pop.popdown();
							this.delete_connection(menu_conn);
						});
						box.append(del_item);
					}
					pop.child = box;
					pop.set_parent(row_box);
					pop.pointing_to = Gdk.Rectangle() { x = (int) x, y = (int) y, width = 1, height = 1 };
					pop.popup();
				});
				row_box.add_controller(menu_click);
				var expander = new Gtk.TreeExpander() {
					child = row_box
				};
				list_item.child = expander;
				list_item.bind_property("item", expander, "list-row", GLib.BindingFlags.SYNC_CREATE);
				new Gtk.PropertyExpression(
					typeof(Connection),
					new Gtk.PropertyExpression(
						typeof(Gtk.TreeListRow),
						new Gtk.PropertyExpression(typeof(Gtk.ListItem), null, "item"),
						"item"
					),
					"name"
				).bind(name_label, "label", list_item);
				new Gtk.PropertyExpression(
					typeof(Connection),
					new Gtk.PropertyExpression(
						typeof(Gtk.TreeListRow),
						new Gtk.PropertyExpression(typeof(Gtk.ListItem), null, "item"),
						"item"
					),
					"hide-expander"
				).bind(expander, "hide-expander", list_item);
			});
			factory.bind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var expander = list_item.child as Gtk.TreeExpander;
				if (expander == null) {
					return;
				}
				var row_box = expander.child as Gtk.Box;
				if (row_box == null) {
					return;
				}
				var type_icon = row_box.get_first_child() as Gtk.Image;
				var mark_box = row_box.get_last_child() as Gtk.Box;
				if (type_icon == null || mark_box == null) {
					return;
				}
				var row = list_item.item as Gtk.TreeListRow;
				var conn = row != null ? row.item as Connection : null;
				if (conn == null) {
					return;
				}
				row_box.set_data("menu-conn", conn);
				if (conn.is_group) {
					type_icon.icon_name = "folder";
				}
				if (conn.is_local) {
					type_icon.icon_name = "computer";
				}
				if (conn.local_path) {
					type_icon.icon_name = "folder";
				}
				if (!conn.is_group && !conn.is_local && !conn.local_path && conn.lxc_container) {
					type_icon.icon_name = "drive-harddisk";
				}
				if (!conn.is_group && !conn.is_local && !conn.local_path && !conn.lxc_container
						&& conn.sudo_after_login) {
					type_icon.icon_name = "security-high";
				}
				if (!conn.is_group && !conn.is_local && !conn.local_path && !conn.lxc_container
						&& !conn.sudo_after_login) {
					type_icon.icon_name = "video-display";
				}
				var old_nid = mark_box.get_data<ulong>("nid");
				var old_conn = mark_box.get_data<Connection>("conn");
				if (old_conn != null && old_nid != 0) {
					old_conn.disconnect(old_nid);
				}
				mark_box.set_data<ulong>("nid", 0);

				while (mark_box.get_first_child() != null) {
					mark_box.remove(mark_box.get_first_child());
				}
				this.fill_session_marks(mark_box, conn);
				var nid = conn.notify.connect((o, pspec) => {
					if (pspec.name != "open-count" && pspec.name != "active-tab"
							&& pspec.name != "tab-titles" && pspec.name != "tab-states") {
						return;
					}
					while (mark_box.get_first_child() != null) {
						mark_box.remove(mark_box.get_first_child());
					}
					this.fill_session_marks(mark_box, conn);
				});
				mark_box.set_data<ulong>("nid", nid);
				mark_box.set_data<Connection>("conn", conn);
			});
			factory.unbind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var expander = list_item.child as Gtk.TreeExpander;
				if (expander == null) {
					return;
				}
				var row_box = expander.child as Gtk.Box;
				if (row_box == null) {
					return;
				}
				var mark_box = row_box.get_last_child() as Gtk.Box;
				if (mark_box == null) {
					return;
				}
				var nid = mark_box.get_data<ulong>("nid");
				var conn = mark_box.get_data<Connection>("conn");
				if (conn == null || nid == 0) {
					return;
				}
				conn.disconnect(nid);
				mark_box.set_data<ulong>("nid", 0);
			});

			this.list_view = new Gtk.ListView(this.selection, factory) {
				single_click_activate = false,
				hexpand = true,
				vexpand = true
			};
			this.list_view.activate.connect((pos) => {
				this.selection.selected = pos;
				var row = this.selection.selected_item as Gtk.TreeListRow;
				var conn = row != null ? row.item as Connection : null;
				if (conn == null || conn.is_group) {
					return;
				}
				this.connection_activated(conn);
			});

			var scrolled = new Gtk.ScrolledWindow() {
				child = this.list_view,
				hexpand = true,
				vexpand = true,
				overlay_scrolling = false,
				hscrollbar_policy = Gtk.PolicyType.NEVER
			};
			this.append(scrolled);
		}

		/**
		 * Build right-side session icons for ``conn`` into ``mark_box``.
		 *
		 * @param mark_box Container for icons
		 * @param conn Host row
		 */
		private void fill_session_marks(Gtk.Box mark_box, Connection conn)
		{
			for (var i = 0; i < conn.open_count; i++) {
				var idx = i;
				var tip = conn.name;
				if (idx < conn.tab_titles.size && conn.tab_titles.get(idx).length > 0) {
					tip = conn.tab_titles.get(idx);
				}
				var mark = SessionState.IDLE;
				if (idx < conn.tab_states.size) {
					mark = conn.tab_states.get(idx);
				}
				var is_active = idx == conn.active_tab;
				var btn = new Gtk.Button() {
					has_frame = false,
					focus_on_click = false,
					tooltip_text = tip
				};
				if (!is_active && mark == SessionState.BUSY) {
					btn.child = new Gtk.Spinner() {
						spinning = true,
						width_request = 16,
						height_request = 16
					};
				} else {
					btn.icon_name = "video-display";
				}
				btn.add_css_class("flat");
				btn.add_css_class("session-icon");
				if (is_active) {
					btn.add_css_class("session-active");
				} else {
					switch (mark) {
						case SessionState.BUSY:
							btn.add_css_class("session-busy");
							break;

						case SessionState.READY:
							btn.add_css_class("session-ready");
							break;

						case SessionState.DEAD:
							btn.add_css_class("session-dead");
							break;

						default:
							btn.add_css_class("session-idle");
							break;
					}
				}
				btn.clicked.connect(() => {
					this.terminal_selected(conn, idx);
				});
				mark_box.append(btn);
			}
		}
	}
}
