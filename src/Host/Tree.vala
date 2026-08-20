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

namespace RooTerm.Host
{
	/**
	 * Ásbrú host/group tree (single-click selects; double-click reserved for open).
	 * One terminal icon per open tab; active tab icon is green and clickable.
	 */
	public class Tree : Gtk.Box
	{
		private Gtk.ListView list_view;
		public Gtk.SingleSelection selection;
		private Gtk.TreeListModel tree_model;
		private Gtk.CustomFilter open_filter;
		private TreeMenu menu;
		/**
		 * Name-match uuids plus parents of those matches (path to the hit).
		 * Children of a match are not in this set; the filter tests ancestor names.
		 */
		private Gee.HashSet<string> search_uuids = new Gee.HashSet<string>();
		private Gee.ArrayList<Connection> search_hits = new Gee.ArrayList<Connection>();
		/**
		 * When false, hide rows that are not open and not a parent of an open row.
		 * When true, the full tree is shown. Bottom toggle binds this.
		 * Typing in search sets this true;
		 * open or select of an open host clears it.
		 */
		public bool show_all { get; set; default = false; }
		/**
		 * Case-insensitive substring filter on {@link Connection.name}.
		 * Empty: open-only / show-all as usual. Non-empty: a row is visible
		 * if it is a name match or a parent of one, or an ancestor's name matches
		 * (matched host / group still shows its children; siblings of a hit do not).
		 * Bound to the search entry.
		 */
		public string search { get; set; default = ""; }
		/**
		 * Row under the context menu. Separate from {@link selection} (active
		 * terminal); drives the ``menu-target`` row chrome only.
		 */
		public Connection? menu_target { get; set; default = null; }
		/**
		 * Search keyboard cursor. Separate from {@link selection} (active
		 * terminal); {@link search_step} / {@link search_pick} drive it.
		 */
		public Connection? search_target { get; set; default = null; }

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
		 * Highlight ``connection`` in the tree (no spawn).
		 * Parents are expanded first so the row is in the flattened list.
		 *
		 * @param connection Host to select (same instance as in the config tree)
		 */
		public void select(Connection connection)
		{
			while (connection.tree_row == null && connection.parent != null) {
				var up = connection.parent;
				while (up != null && up.tree_row == null) {
					up = up.parent;
				}
				if (up == null) {
					break;
				}
				up.tree_row.expanded = true;
			}
			if (connection.tree_row == null) {
				return;
			}
			var i = connection.tree_row.get_position();
			this.selection.selected = i;
			this.list_view.scroll_to(i, Gtk.ListScrollFlags.NONE, null);
		}

		/**
		 * Move {@link search_target} by ``delta`` entries in {@link search_hits}.
		 * Does not change {@link selection}. Wraps past either end.
		 *
		 * @param delta ``1`` Down, ``-1`` Up
		 */
		private void search_step(int delta)
		{
			if (this.search == "" || this.search_hits.size == 0) {
				return;
			}
			var i = -1;
			if (this.search_target != null) {
				i = this.search_hits.index_of(this.search_target);
			}
			if (i < 0) {
				i = delta > 0 ? -1 : this.search_hits.size;
			}
			i += delta;
			if (i < 0) {
				i = this.search_hits.size - 1;
			}
			if (i >= this.search_hits.size) {
				i = 0;
			}
			var hit = this.search_hits.get(i);
			if (hit == this.search_target) {
				return;
			}
			if (this.search_target != null) {
				this.search_target.search_css = "";
			}
			this.search_target = hit;
			this.search_target.search_css = "search-target";
			if (this.search_target.tree_row == null) {
				return;
			}
			this.list_view.scroll_to(this.search_target.tree_row.get_position(), Gtk.ListScrollFlags.NONE, null);
		}

		/**
		 * Apply the search cursor: select an open row, otherwise activate.
		 */
		private void search_pick()
		{
			if (this.search_target == null) {
				return;
			}
			if (this.search_target.sessions.get_n_items() > 0) {
				this.select(this.search_target);
				return;
			}
			this.connection_activated(this.search_target);
		}

		/**
		 * Build tree UI bound to ``window.tree`` (live root {@link TreeNodes}).
		 *
		 * @param window Main window (passed to {@link TreeMenu})
		 */
		public Tree(RooTerm.MainWindow window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				hexpand: false,
				vexpand: true
			);

			var hint = new Gtk.Label("Click to show\nall hosts") {
				justify = Gtk.Justification.CENTER,
				valign = Gtk.Align.END,
				halign = Gtk.Align.CENTER,
				can_target = false,
				hexpand = true,
				visible = false,
				margin_bottom = 16,
				margin_start = 8,
				margin_end = 8
			};
			hint.add_css_class("open-hint");
			var prev_open = window.tree.num_open;
			this.open_filter = new Gtk.CustomFilter((item) => {
				var conn = item as Connection;
				if (conn == null) {
					return false;
				}
				if (this.search != "") {
					if (this.search_uuids.contains(conn.uuid)) {
						return true;
					}
					var needle = this.search.casefold();
					var up = conn.parent;
					while (up != null) {
						if (up.name.casefold().contains(needle)) {
							return true;
						}
						up = up.parent;
					}
					return false;
				}
				if (this.show_all || window.tree.num_open == 0) {
					return true;
				}
				return conn.sessions.get_n_items() > 0 || conn.children_open > 0;
			});
			window.tree.open_changed.connect(() => {
				this.open_filter.changed(Gtk.FilterChange.DIFFERENT);
				if (this.show_all && window.tree.num_open > prev_open) {
					this.show_all = false;
					this.search = "";
				}
				prev_open = window.tree.num_open;
				hint.visible = !this.show_all && this.search == "" && window.tree.num_open > 0;
				if (this.search != "" || !this.show_all) {
					window.tree.expand_all();
				}
			});
			this.notify["show-all"].connect(() => {
				if (!this.show_all && this.search != "") {
					this.search = "";
				}
				this.open_filter.changed(Gtk.FilterChange.DIFFERENT);
				hint.visible = !this.show_all && this.search == "" && window.tree.num_open > 0;
				window.tree.expand_all();
			});
			this.notify["search"].connect(() => {
				this.search_uuids.clear();
				this.search_hits.clear();
				if (this.search_target != null) {
					this.search_target.search_css = "";
				}
				this.search_target = null;
				if (this.search == "") {
					this.open_filter.changed(Gtk.FilterChange.DIFFERENT);
					hint.visible = !this.show_all && window.tree.num_open > 0;
					window.tree.expand_all();
					return;
				}
				var needle = this.search.casefold();
				foreach (var conn in window.tree.by_uuid.values) {
					if (!conn.name.casefold().contains(needle)) {
						continue;
					}
					this.search_uuids.add(conn.uuid);
					var up = conn.parent;
					while (up != null) {
						this.search_uuids.add(up.uuid);
						up = up.parent;
					}
				}
				var pending = new Gee.ArrayList<Connection>();
				for (var i = window.tree.size - 1; i >= 0; i--) {
					pending.add(window.tree.get(i));
				}
				while (pending.size > 0) {
					var conn = pending.get(pending.size - 1);
					pending.remove_at(pending.size - 1);
					for (var c = conn.children.size - 1; c >= 0; c--) {
						pending.add(conn.children.get(c));
					}
					if (conn.kind == ConnectionKind.GROUP) {
						continue;
					}
					if (this.search_uuids.contains(conn.uuid)) {
						this.search_hits.add(conn);
						continue;
					}
					var up = conn.parent;
					while (up != null) {
						if (up.name.casefold().contains(needle)) {
							this.search_hits.add(conn);
							break;
						}
						up = up.parent;
					}
				}
				this.show_all = true;
				this.open_filter.changed(Gtk.FilterChange.DIFFERENT);
				hint.visible = false;
				window.tree.expand_all();
				GLib.Idle.add(() => {
					this.search_step(1);
					return false;
				});
			});
			this.tree_model = new Gtk.TreeListModel(
				new Gtk.FilterListModel(window.tree, this.open_filter),
				false,
				false,
				(item) => {
					var conn = item as Connection;
					if (conn == null) {
						return null;
					}
					return new Gtk.FilterListModel(conn.children, this.open_filter);
				}
			);
			this.tree_model.items_changed.connect((pos, removed, added) => {
				for (var i = 0; i < added; i++) {
					var row = this.tree_model.get_item(pos + i) as Gtk.TreeListRow;
					if (row == null) {
						continue;
					}
					var conn = row.item as Connection;
					if (conn == null) {
						continue;
					}
					conn.tree_row = row;
				}
			});
			for (var i = 0; i < this.tree_model.get_n_items(); i++) {
				var row = this.tree_model.get_item(i) as Gtk.TreeListRow;
				if (row == null) {
					continue;
				}
				var conn = row.item as Connection;
				if (conn == null) {
					continue;
				}
				conn.tree_row = row;
			}
			window.tree.expand_all();

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
				if (!this.show_all && this.search == "") {
					return;
				}
				if (conn.sessions.get_n_items() == 0 && conn.children_open == 0) {
					return;
				}
				this.show_all = false;
				this.search = "";
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
				new Gtk.PropertyExpression(
					typeof(Connection),
					new Gtk.PropertyExpression(
						typeof(Gtk.TreeListRow),
						new Gtk.PropertyExpression(typeof(Gtk.ListItem), null, "item"),
						"item"
					),
					"search-css"
				).bind(expander, "name", list_item);
			});
			factory.bind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var expander = (Gtk.TreeExpander) list_item.child;
				var row_box = (Gtk.Box) expander.child;
				var mark_box = (Gtk.Box) row_box.get_last_child();
				var list_row = (Gtk.TreeListRow) list_item.item;
				var conn = (Connection) list_row.item;
				if ((conn.kind == ConnectionKind.GROUP || conn.kind == ConnectionKind.LOCAL || conn.lxc_host)
					&& conn.expand_binding == null) {
					conn.expand_binding = conn.bind_property(
						"expanded",
						list_row,
						"expanded",
						GLib.BindingFlags.BIDIRECTIONAL
					);
				}
				var old_sid = mark_box.get_data<ulong>("sessions-sid");
				if (old_sid != 0) {
					mark_box.get_data<GLib.ListStore>("sessions").disconnect(old_sid);
				}
				while (mark_box.get_first_child() != null) {
					mark_box.remove(mark_box.get_first_child());
				}
				for (var i = 0; i < conn.sessions.get_n_items(); i++) {
					this.append_session_mark(mark_box, conn, (Terminal.Base) conn.sessions.get_item(i), i);
				}
				mark_box.set_data<GLib.ListStore>("sessions", conn.sessions);
				mark_box.set_data<ulong>("sessions-sid", conn.sessions.items_changed.connect((p, r, a) => {
					while (mark_box.get_first_child() != null) {
						mark_box.remove(mark_box.get_first_child());
					}
					for (var i = 0; i < conn.sessions.get_n_items(); i++) {
						this.append_session_mark(mark_box, conn, (Terminal.Base) conn.sessions.get_item(i), i);
					}
				}));
				var old_menu_sid = expander.get_data<ulong>("menu-target-sid");
				if (old_menu_sid != 0) {
					this.disconnect(old_menu_sid);
				}
				expander.remove_css_class("menu-target");
				if (conn == this.menu_target) {
					expander.add_css_class("menu-target");
				}
				expander.set_data<ulong>("menu-target-sid", this.notify["menu-target"].connect(() => {
					if (conn == this.menu_target) {
						expander.add_css_class("menu-target");
					} else {
						expander.remove_css_class("menu-target");
					}
				}));
			});
			factory.unbind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var expander = (Gtk.TreeExpander) list_item.child;
				var mark_box = (Gtk.Box) ((Gtk.Box) expander.child).get_last_child();
				var list_row = list_item.item as Gtk.TreeListRow;
				var unbound = list_row != null ? list_row.item as Connection : null;
				if (unbound != null && unbound.expand_binding != null) {
					unbound.expand_binding.unbind();
					unbound.expand_binding = null;
				}
				var sid = mark_box.get_data<ulong>("sessions-sid");
				if (sid != 0) {
					mark_box.get_data<GLib.ListStore>("sessions").disconnect(sid);
					mark_box.set_data<ulong>("sessions-sid", 0);
				}
				var menu_sid = expander.get_data<ulong>("menu-target-sid");
				if (menu_sid != 0) {
					this.disconnect(menu_sid);
					expander.set_data<ulong>("menu-target-sid", 0);
				}
				expander.remove_css_class("menu-target");
			});

			this.list_view = new Gtk.ListView(this.selection, factory) {
				single_click_activate = false,
				hexpand = true,
				vexpand = true
			};
			this.menu = new TreeMenu(window, this);
			this.menu.set_parent(this.list_view);
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
							this.menu.popup_for(menu_conn, x, y);
						}
						return;
					}
					picked = picked.get_parent();
				}
				this.menu.popup_for(null, x, y);
			});
			this.list_view.add_controller(menu_click);
			var empty_click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_PRIMARY
			};
			empty_click.pressed.connect((n_press, x, y) => {
				if (this.show_all) {
					return;
				}
				var picked = this.list_view.pick((float) x, (float) y, Gtk.PickFlags.DEFAULT);
				if (picked != null && picked != this.list_view) {
					return;
				}
				this.show_all = true;
			});
			this.list_view.add_controller(empty_click);
			var search_keys = new Gtk.EventControllerKey() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			search_keys.key_pressed.connect((keyval, keycode, state) => {
				if (this.search == "") {
					return false;
				}
				switch (keyval) {
					case Gdk.Key.Up:
						this.search_step(-1);
						return true;

					case Gdk.Key.Down:
						this.search_step(1);
						return true;

					case Gdk.Key.Return:
					case Gdk.Key.KP_Enter:
						this.search_pick();
						return true;

					default:
						return false;
				}
			});
			window.host_search.add_controller(search_keys);
			this.list_view.activate.connect((pos) => {
				this.selection.selected = pos;
				var row = this.selection.selected_item as Gtk.TreeListRow;
				var conn = row != null ? row.item as Connection : null;
				if (conn == null || conn.kind == ConnectionKind.GROUP) {
					return;
				}
				this.connection_activated(conn);
			});

			var overlay = new Gtk.Overlay() {
				child = this.list_view,
				hexpand = true,
				vexpand = true
			};
			overlay.add_overlay(hint);
			var scrolled = new Gtk.ScrolledWindow() {
				child = overlay,
				hexpand = true,
				vexpand = true,
				overlay_scrolling = false,
				hscrollbar_policy = Gtk.PolicyType.NEVER
			};
			this.append(scrolled);
		}

		/**
		 * One tree session-mark button for ``term`` (state / label live on the terminal).
		 */
		private void append_session_mark(Gtk.Box mark_box, Connection conn, Terminal.Base term, int index)
		{
			var btn = new Gtk.Button() {
				has_frame = false,
				focus_on_click = false,
				tooltip_text = term.label()
			};
			btn.add_css_class("flat");
			btn.add_css_class("session-icon");
			btn.add_css_class(term.session_css);
			if (!term.tree_active && term.state == Session.State.BUSY) {
				btn.child = new Gtk.Spinner() {
					spinning = true,
					width_request = 16,
					height_request = 16
				};
			} else {
				btn.child = new Gtk.Image.from_icon_name("video-display") {
					pixel_size = 16
				};
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
				btn.remove_css_class("session-exited");
				btn.add_css_class(term.session_css);
				if (!term.tree_active && term.state == Session.State.BUSY) {
					btn.child = new Gtk.Spinner() {
						spinning = true,
						width_request = 16,
						height_request = 16
					};
				} else {
					btn.child = new Gtk.Image.from_icon_name("video-display") {
						pixel_size = 16
					};
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
				this.show_all = false;
				this.search = "";
				this.terminal_selected(conn, index);
			});
			mark_box.append(btn);
		}
	}
}
