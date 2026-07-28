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
		 * Emitted for Localhost / path context menu **New terminal**.
		 *
		 * @param connection Localhost root or a {@link ConnectionKind.LOCAL_PATH} row
		 */
		public signal void new_local(Connection connection);

		/**
		 * Emitted for path context menu **Close**.
		 *
		 * @param connection {@link ConnectionKind.LOCAL_PATH} row to close
		 */
		public signal void close_local(Connection connection);

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
				if (conn == null || conn.kind == ConnectionKind.GROUP) {
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
					"tree-icon"
				).bind(type_icon, "icon-name", list_item);
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
				var expander = (Gtk.TreeExpander) list_item.child;
				var row_box = (Gtk.Box) expander.child;
				var mark_box = (Gtk.Box) row_box.get_last_child();
				var conn = (Connection) ((Gtk.TreeListRow) list_item.item).item;
				var old_sid = mark_box.get_data<ulong>("sessions-sid");
				if (old_sid != 0) {
					mark_box.get_data<GLib.ListStore>("sessions").disconnect(old_sid);
				}
				while (mark_box.get_first_child() != null) {
					mark_box.remove(mark_box.get_first_child());
				}
				for (var i = 0; i < conn.sessions.get_n_items(); i++) {
					this.append_session_mark(mark_box, conn, (Terminal) conn.sessions.get_item(i), i);
				}
				mark_box.set_data<GLib.ListStore>("sessions", conn.sessions);
				mark_box.set_data<ulong>("sessions-sid", conn.sessions.items_changed.connect((p, r, a) => {
					while (mark_box.get_first_child() != null) {
						mark_box.remove(mark_box.get_first_child());
					}
					for (var i = 0; i < conn.sessions.get_n_items(); i++) {
						this.append_session_mark(mark_box, conn, (Terminal) conn.sessions.get_item(i), i);
					}
				}));
			});
			factory.unbind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var expander = (Gtk.TreeExpander) list_item.child;
				var mark_box = (Gtk.Box) ((Gtk.Box) expander.child).get_last_child();
				var sid = mark_box.get_data<ulong>("sessions-sid");
				if (sid != 0) {
					mark_box.get_data<GLib.ListStore>("sessions").disconnect(sid);
					mark_box.set_data<ulong>("sessions-sid", 0);
				}
			});

			this.list_view = new Gtk.ListView(this.selection, factory) {
				single_click_activate = false,
				hexpand = true,
				vexpand = true
			};
			var menu_click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY
			};
			menu_click.pressed.connect((n_press, x, y) => {
				var picked = this.list_view.pick((float) x, (float) y, Gtk.PickFlags.DEFAULT);
				while (picked != null && !(picked is Gtk.ListView)) {
					var expander = picked as Gtk.TreeExpander;
					if (expander != null && expander.list_row != null) {
						var menu_conn = expander.list_row.item as Connection;
						if (menu_conn != null) {
							this.popup_menu(this.list_view, menu_conn, x, y);
						}
						return;
					}
					picked = picked.get_parent();
				}
			});
			this.list_view.add_controller(menu_click);
			this.list_view.activate.connect((pos) => {
				this.selection.selected = pos;
				var row = this.selection.selected_item as Gtk.TreeListRow;
				var conn = row != null ? row.item as Connection : null;
				if (conn == null || conn.kind == ConnectionKind.GROUP) {
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
		 * Context menu for ``menu_conn`` at the click point on ``row_box``.
		 */
		private void popup_menu(Gtk.Widget row_box, Connection menu_conn, double x, double y)
		{
			var pop = new Gtk.Popover();
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			switch (menu_conn.kind) {
				case ConnectionKind.LOCAL:
					var new_item = new Gtk.Button.with_label("New terminal") {
						has_frame = false,
						halign = Gtk.Align.FILL
					};
					new_item.clicked.connect(() => {
						pop.popdown();
						this.new_local(menu_conn);
					});
					box.append(new_item);
					break;

				case ConnectionKind.LOCAL_PATH:
					var path_new = new Gtk.Button.with_label("New terminal here") {
						has_frame = false,
						halign = Gtk.Align.FILL
					};
					path_new.clicked.connect(() => {
						pop.popdown();
						this.new_local(menu_conn);
					});
					box.append(path_new);
					var close_item = new Gtk.Button.with_label("Close") {
						has_frame = false,
						halign = Gtk.Align.FILL
					};
					close_item.clicked.connect(() => {
						pop.popdown();
						this.close_local(menu_conn);
					});
					box.append(close_item);
					break;

				case ConnectionKind.GROUP:
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
					var group_del = new Gtk.Button.with_label("Delete") {
						has_frame = false,
						halign = Gtk.Align.FILL,
						sensitive = can_delete
					};
					group_del.clicked.connect(() => {
						pop.popdown();
						this.delete_connection(menu_conn);
					});
					box.append(group_del);
					break;

				case ConnectionKind.HOST:
				case ConnectionKind.LXC:
					var edit_item = new Gtk.Button.with_label("Edit connection") {
						has_frame = false,
						halign = Gtk.Align.FILL
					};
					edit_item.clicked.connect(() => {
						pop.popdown();
						this.edit_connection(menu_conn);
					});
					box.append(edit_item);
					if (menu_conn.kind == ConnectionKind.HOST && menu_conn.lxc_host) {
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
					var host_del = new Gtk.Button.with_label("Delete") {
						has_frame = false,
						halign = Gtk.Align.FILL
					};
					host_del.clicked.connect(() => {
						pop.popdown();
						this.delete_connection(menu_conn);
					});
					box.append(host_del);
					break;
			}
			pop.child = box;
			pop.set_parent(row_box);
			pop.pointing_to = Gdk.Rectangle() { x = (int) x, y = (int) y, width = 1, height = 1 };
			pop.popup();
		}

		/**
		 * One tree session-mark button for ``term`` (state / label live on the terminal).
		 */
		private void append_session_mark(Gtk.Box mark_box, Connection conn, Terminal term, int index)
		{
			var btn = new Gtk.Button() {
				has_frame = false,
				focus_on_click = false,
				tooltip_text = term.label()
			};
			btn.add_css_class("flat");
			btn.add_css_class("session-icon");
			btn.add_css_class(term.session_css);
			if (!term.tree_active && term.state == SessionState.BUSY) {
				btn.child = new Gtk.Spinner() {
					spinning = true,
					width_request = 16,
					height_request = 16
				};
			} else {
				btn.icon_name = "video-display";
			}
			var state_sid = term.notify.connect((o, pspec) => {
				if (pspec.name != "session-css" && pspec.name != "state" && pspec.name != "tree-active") {
					return;
				}
				btn.remove_css_class("session-active");
				btn.remove_css_class("session-idle");
				btn.remove_css_class("session-busy");
				btn.remove_css_class("session-ready");
				btn.remove_css_class("session-dead");
				btn.add_css_class(term.session_css);
				if (!term.tree_active && term.state == SessionState.BUSY) {
					btn.child = new Gtk.Spinner() {
						spinning = true,
						width_request = 16,
						height_request = 16
					};
				} else {
					btn.icon_name = "video-display";
				}
			});
			var label_sid = term.label_changed.connect(() => {
				btn.tooltip_text = term.label();
			});
			btn.destroy.connect(() => {
				term.disconnect(state_sid);
				term.disconnect(label_sid);
			});
			btn.clicked.connect(() => {
				this.terminal_selected(conn, index);
			});
			mark_box.append(btn);
		}
	}
}
