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
		private GLib.ListStore root_store;
		/**
		 * Flat DFS list of the same {@link Connection} instances as the expanded tree
		 * (for {@link GLib.ListStore.find} in {@link select}).
		 */
		private GLib.ListStore hosts;

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
		 * Emitted for context menu **Delete** (after the user picks the item; confirm in window).
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
			uint pos;
			if (!this.hosts.find(connection, out pos)) {
				return;
			}
			this.selection.selected = pos;
			this.list_view.scroll_to(pos, Gtk.ListScrollFlags.NONE, null);
		}

		/**
		 * Replace tree contents from a loaded {@link Config}.
		 *
		 * @param config Loaded RooTerm config
		 */
		public void fill(Config config)
		{
			this.root_store.remove_all();
			this.hosts.remove_all();

			var walk = new Gee.ArrayList<Connection>();
			foreach (var root in config.roots) {
				if (root.deleted) {
					continue;
				}
				this.root_store.append(root);
			}
			for (var i = config.roots.size - 1; i >= 0; i--) {
				walk.add(config.roots.get(i));
			}
			while (walk.size > 0) {
				var conn = walk.remove_at(walk.size - 1);
				if (conn.deleted) {
					continue;
				}
				this.hosts.append(conn);
				for (var i = conn.children.size - 1; i >= 0; i--) {
					walk.add(conn.children.get(i));
				}
			}
		}

		/**
		 * Build empty tree UI; call {@link fill} with config.
		 */
		public HostTree()
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				hexpand: false,
				vexpand: true
			);

			this.root_store = new GLib.ListStore(typeof(Connection));
			this.hosts = new GLib.ListStore(typeof(Connection));

			this.tree_model = new Gtk.TreeListModel(
				this.root_store,
				false,
				true,
				(item) => {
					var conn = item as Connection;
					if (conn == null || conn.children.size == 0) {
						return null;
					}
					var child_store = new GLib.ListStore(typeof(Connection));
					foreach (var child in conn.children) {
						if (child.deleted) {
							continue;
						}
						child_store.append(child);
					}
					if (child_store.get_n_items() == 0) {
						return null;
					}
					return child_store;
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
					if (menu_conn == null) {
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
				if (!conn.is_group) {
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
