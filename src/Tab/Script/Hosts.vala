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

namespace RooTerm.Tab.Script
{
	/**
	 * Host picker for {@link RooTerm.Dialog.Script}.
	 *
	 * The grid is the existing host tree, with the same expander
	 * indent. A tick still asks {@link RooTerm.Store.TaskTarget.save}.
	 * Clearing the tick asks {@link RooTerm.Store.TaskTarget.remove}.
	 * Ticks stay while the same command is being tested. {@link Edit.load}
	 * clears them.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var hosts = new RooTerm.Tab.Script.Hosts(sender);
	 * }}}
	 */
	public class Hosts : Gtk.Box
	{
		/**
		 * Checkboxes refresh after Select all changes the ticks.
		 */
		public signal void picks_changed();

		private weak RooTerm.Dialog.Script sender;
		/**
		 * Host tree shown in the grid.
		 */
		public Host.TreeNodes nodes;
		/**
		 * Draft task for this visit. Id 0 until the first Run/Test.
		 */
		public RooTerm.SQT.Task task {
			get; set; default = new RooTerm.SQT.Task();
		}
		/**
		 * Command whose ticks this page is holding.
		 */
		public RooTerm.SQT.Script script {
			get; set; default = new RooTerm.SQT.Script();
		}
		/**
		 * Tasks for {@link task}.
		 */
		public RooTerm.Store.Task tasks;
		/**
		 * Ticked rows for {@link task}.
		 */
		public RooTerm.Store.TaskTarget targets;
		/**
		 * Connection id to task-target id.
		 */
		public Gee.HashMap<int, int> picks {
			get; set; default = new Gee.HashMap<int, int>();
		}
		private RooTerm.Filter.Plan filter;
		private Gtk.TreeListModel tree_model;
		private Gtk.SearchEntry search;
		private Gtk.Button select;
		private Adw.ToggleGroup scopes;
		private Gtk.Stack body;

		/**
		 * @param sender script sender window
		 */
		public Hosts(RooTerm.Dialog.Script sender)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				hexpand: true,
				vexpand: true
			);
			this.sender = sender;
			this.nodes = sender.main.tree;
			this.tasks = new RooTerm.Store.Task(sender.main.tree.db);
			this.targets = new RooTerm.Store.TaskTarget(sender.main.tree.db);
			this.filter = new RooTerm.Filter.Plan();
			var root = new Gtk.FilterListModel(sender.main.tree, this.filter) {
				incremental = false
			};
			this.tree_model = new Gtk.TreeListModel(root, false, false, (item) => {
				var conn = item as Host.Connection;
				if (conn == null || conn.children.size == 0) {
					return null;
				}
				return new Gtk.FilterListModel(conn.children, this.filter) {
					incremental = false
				};
			});
			var grid = new Gtk.ColumnView(new Gtk.SingleSelection(this.tree_model)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			var checks = new Gtk.SignalListItemFactory();
			checks.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.CheckButton() {
					halign = Gtk.Align.CENTER,
					valign = Gtk.Align.CENTER
				};
			});
			checks.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var list_row = (Gtk.TreeListRow) item.item;
				var conn = (Host.Connection) list_row.item;
				var check = (Gtk.CheckButton) item.child;
				var old = check.get_data<ulong>("pick-sid");
				if (old != 0) {
					check.disconnect(old);
					check.set_data<ulong>("pick-sid", 0);
				}
				var old_sync = check.get_data<ulong>("sync-sid");
				if (old_sync != 0) {
					this.disconnect(old_sync);
					check.set_data<ulong>("sync-sid", 0);
				}
				switch (conn.kind) {
					case Host.ConnectionKind.HOST:
					case Host.ConnectionKind.LXC:
						break;

					default:
						check.visible = false;
						check.active = false;
						return;
				}
				check.visible = true;
				check.set_data<int>("silence", 1);
				check.active = this.picks.has_key((int) conn.id);
				check.set_data<int>("silence", 0);
				check.set_data<ulong>("pick-sid", check.notify["active"].connect(() => {
					if (check.get_data<int>("silence") != 0) {
						return;
					}
					var id = (int) conn.id;
					if (check.active && !this.picks.has_key(id)) {
						var target = new RooTerm.SQT.TaskTarget() {
							task_id = this.task.id,
							agent_id = conn.id
						};
						this.targets.save(target);
						this.picks.set(id, (int) target.id);
					}
					if (!check.active && this.picks.has_key(id)) {
						var target = new RooTerm.SQT.TaskTarget() {
							id = this.picks.get(id)
						};
						this.targets.remove(target);
						this.picks.unset(id);
					}
					this.refresh_select();
				}));
				check.set_data<ulong>("sync-sid", this.picks_changed.connect(() => {
					var want = this.picks.has_key((int) conn.id);
					if (check.active == want) {
						return;
					}
					check.set_data<int>("silence", 1);
					check.active = want;
					check.set_data<int>("silence", 0);
				}));
			});
			checks.unbind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				if (item.child == null) {
					return;
				}
				var check = (Gtk.CheckButton) item.child;
				var old = check.get_data<ulong>("pick-sid");
				if (old != 0) {
					check.disconnect(old);
					check.set_data<ulong>("pick-sid", 0);
				}
				var old_sync = check.get_data<ulong>("sync-sid");
				if (old_sync != 0) {
					this.disconnect(old_sync);
					check.set_data<ulong>("sync-sid", 0);
				}
			});
			grid.append_column(new Gtk.ColumnViewColumn("", checks) {
				fixed_width = 48
			});
			var names = new Gtk.SignalListItemFactory();
			names.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var icon = new Gtk.Image() {
					pixel_size = 16,
					valign = Gtk.Align.CENTER
				};
				var label = new Gtk.Label("") {
					xalign = 0,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END
				};
				var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
				row_box.append(icon);
				row_box.append(label);
				var expander = new Gtk.TreeExpander() {
					child = row_box,
					hexpand = true
				};
				item.child = expander;
				item.bind_property("item", expander, "list-row", GLib.BindingFlags.SYNC_CREATE);
				new Gtk.PropertyExpression(
					typeof(Host.Connection),
					new Gtk.PropertyExpression(
						typeof(Gtk.TreeListRow),
						new Gtk.PropertyExpression(typeof(Gtk.ListItem), null, "item"),
						"item"
					),
					"name"
				).bind(label, "label", item);
				new Gtk.PropertyExpression(
					typeof(Host.Connection),
					new Gtk.PropertyExpression(
						typeof(Gtk.TreeListRow),
						new Gtk.PropertyExpression(typeof(Gtk.ListItem), null, "item"),
						"item"
					),
					"tree-icon"
				).bind(icon, "icon-name", item);
				new Gtk.PropertyExpression(
					typeof(Host.Connection),
					new Gtk.PropertyExpression(
						typeof(Gtk.TreeListRow),
						new Gtk.PropertyExpression(typeof(Gtk.ListItem), null, "item"),
						"item"
					),
					"hide-expander"
				).bind(expander, "hide-expander", item);
			});
			grid.append_column(new Gtk.ColumnViewColumn("Host", names) {
				expand = true
			});
			this.scopes = new Adw.ToggleGroup();
			this.scopes.add(new Adw.Toggle() {
				name = "hosts",
				label = "Hosts"
			});
			this.scopes.add(new Adw.Toggle() {
				name = "both",
				label = "Hosts + containers"
			});
			this.scopes.add(new Adw.Toggle() {
				name = "containers",
				label = "Containers"
			});
			this.scopes.active_name = "both";
			this.search = new Gtk.SearchEntry() {
				placeholder_text = "Search machines",
				hexpand = true
			};
			this.select = new Gtk.Button.with_label("Select all");
			var empty = new Gtk.Label("No machines") {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.body.add_named(new Gtk.ScrolledWindow() {
				child = grid,
				hexpand = true,
				vexpand = true
			}, "list");
			this.body.add_named(empty, "empty");
			this.body.visible_child_name = "empty";
			var tools = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_start = 16,
				margin_end = 16,
				margin_top = 12,
				margin_bottom = 12
			};
			tools.append(this.search);
			tools.append(this.scopes);
			tools.append(this.select);
			this.append(tools);
			this.append(this.body);
			this.search.search_changed.connect(() => {
				this.filter.search = this.search.text;
				var needle = this.search.text.strip();
				if (needle == "") {
					return;
				}
				var pass = 0;
				GLib.Idle.add(() => {
					if (this.search.text.strip() != needle) {
						return false;
					}
					var open = new Gee.ArrayList<Gtk.TreeListRow>();
					for (var i = 0; i < this.tree_model.get_n_items(); i++) {
						var row = this.tree_model.get_item(i) as Gtk.TreeListRow;
						if (row == null || row.expanded) {
							continue;
						}
						var conn = row.item as Host.Connection;
						if (conn == null || conn.children.size == 0) {
							continue;
						}
						open.add(row);
					}
					for (var i = 0; i < open.size; i++) {
						open.get(i).expanded = true;
					}
					pass++;
					if (open.size == 0 || pass > 8) {
						return false;
					}
					return true;
				});
			});
			this.scopes.notify["active-name"].connect(() => {
				var name = this.scopes.active_name;
				if (name == null || name == "") {
					return;
				}
				this.filter.scope = name;
			});
			this.tree_model.items_changed.connect((position, removed, added) => {
				this.refresh_select();
			});
			this.select.clicked.connect(() => {
				var ids = new Gee.ArrayList<int>();
				var pending = new Gee.ArrayList<Host.Connection>();
				for (var i = 0; i < this.nodes.size; i++) {
					pending.add(this.nodes.get(i));
				}
				var at = 0;
				var all = true;
				while (at < pending.size) {
					var conn = pending.get(at);
					at++;
					for (var i = 0; i < conn.children.size; i++) {
						pending.add(conn.children.get(i));
					}
					if (!this.filter.match(conn)) {
						continue;
					}
					switch (conn.kind) {
						case Host.ConnectionKind.HOST:
						case Host.ConnectionKind.LXC:
							break;

						default:
							continue;
					}
					ids.add((int) conn.id);
					if (!this.picks.has_key((int) conn.id)) {
						all = false;
					}
				}
				if (ids.size == 0) {
					return;
				}
				for (var i = 0; i < ids.size; i++) {
					var id = ids.get(i);
					if (all && this.picks.has_key(id)) {
						var target = new RooTerm.SQT.TaskTarget() {
							id = this.picks.get(id)
						};
						this.targets.remove(target);
						this.picks.unset(id);
						continue;
					}
					if (!all && !this.picks.has_key(id)) {
						var target = new RooTerm.SQT.TaskTarget() {
							task_id = this.task.id,
							agent_id = id
						};
						this.targets.save(target);
						this.picks.set(id, (int) target.id);
					}
				}
				this.picks_changed();
				this.refresh_select();
			});
		}

		/**
		 * Select all becomes Select none when every matching row is ticked.
		 */
		public void refresh_select()
		{
			var total = 0;
			var picked = 0;
			var pending = new Gee.ArrayList<Host.Connection>();
			for (var i = 0; i < this.nodes.size; i++) {
				pending.add(this.nodes.get(i));
			}
			var at = 0;
			while (at < pending.size) {
				var conn = pending.get(at);
				at++;
				for (var i = 0; i < conn.children.size; i++) {
					pending.add(conn.children.get(i));
				}
				if (!this.filter.match(conn)) {
					continue;
				}
				switch (conn.kind) {
					case Host.ConnectionKind.HOST:
					case Host.ConnectionKind.LXC:
						break;

					default:
						continue;
				}
				total++;
				if (this.picks.has_key((int) conn.id)) {
					picked++;
				}
			}
			var all = total > 0 && picked == total;
			this.select.label = all ? "Select none" : "Select all";
			this.sender.run.start_btn.sensitive = picked > 0;
			if (this.tree_model.get_n_items() == 0) {
				this.body.visible_child_name = "empty";
				return;
			}
			this.body.visible_child_name = "list";
		}
	}
}
