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

namespace RooTerm.Dialog
{
	/**
	 * Planning step for one command.
	 *
	 * The grid is the existing host tree, with the same expander
	 * indent. A tick still asks {@link RooTerm.Store.TaskTarget.save}.
	 * Clearing the tick asks {@link RooTerm.Store.TaskTarget.remove}.
	 * Close is on the left. Run is on the right.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var plan = new RooTerm.Dialog.Plan(main, sender);
	 * plan.open(script, main.tree);
	 * }}}
	 */
	public class Plan : Adw.Window
	{
		/**
		 * Checkboxes refresh after Select all changes the ticks.
		 */
		public signal void picks_changed();

		private weak RooTerm.MainWindow main;
		private Host.TreeNodes hosts;
		private RooTerm.SQT.Task task;
		private RooTerm.Store.Task tasks;
		private RooTerm.Store.TaskTarget targets;
		private Gee.HashMap<int, int> picks = new Gee.HashMap<int, int>();
		private RooTerm.Filter.Plan filter;
		private Gtk.TreeListModel tree_model;
		private Gtk.SearchEntry search;
		private Gtk.Button select;
		private Gtk.Button run;
		private Adw.ToggleGroup scopes;
		private Gtk.Stack body;
		private int opened = 0;
		private int goal = 0;
		private bool closing = false;

		/**
		 * @param main Main window (database and Shell)
		 * @param parent Script sender window
		 */
		public Plan(RooTerm.MainWindow main, Gtk.Window parent)
		{
			Object(
				application: main.application,
				title: "Hosts to execute commands",
				transient_for: parent,
				deletable: false,
				hide_on_close: true,
				default_width: 720,
				default_height: 520
			);
			this.main = main;
			this.hosts = main.tree;
			this.task = new RooTerm.SQT.Task();
			this.tasks = new RooTerm.Store.Task(main.tree.db);
			this.targets = new RooTerm.Store.TaskTarget(main.tree.db);
			this.add_css_class("floating-dialog");
			this.filter = new RooTerm.Filter.Plan();
			var root = new Gtk.FilterListModel(main.tree, this.filter) {
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
			var tabs = new Adw.TabView() {
				hexpand = true,
				vexpand = true
			};
			var strip = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2) {
				hexpand = true
			};
			strip.add_css_class("host-tabbar");
			var running = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			running.append(tabs);
			running.append(strip);
			this.body.add_named(running, "run");
			var close = new Gtk.Button.with_label("Close");
			close.clicked.connect(() => {
				this.close();
			});
			this.run = new Gtk.Button.with_label("Run") {
				sensitive = false
			};
			this.run.add_css_class("suggested-action");
			var tools = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_start = 16,
				margin_end = 16,
				margin_top = 12,
				margin_bottom = 12
			};
			tools.append(this.search);
			tools.append(this.scopes);
			tools.append(this.select);
			this.run.clicked.connect(() => {
				if (this.run.label == "Cancel") {
					this.run.sensitive = false;
					return;
				}
				this.task.is_draft = false;
				this.tasks.save(this.task);
				this.run.sensitive = false;
				var chosen = new Gee.ArrayList<Host.Connection>();
				var pending = new Gee.ArrayList<Host.Connection>();
				for (var i = 0; i < this.hosts.size; i++) {
					pending.add(this.hosts.get(i));
				}
				var at = 0;
				while (at < pending.size) {
					var conn = pending.get(at);
					at++;
					for (var i = 0; i < conn.children.size; i++) {
						pending.add(conn.children.get(i));
					}
					if (!this.picks.has_key((int) conn.id)) {
						continue;
					}
					switch (conn.kind) {
						case Host.ConnectionKind.HOST:
						case Host.ConnectionKind.LXC:
							break;

						default:
							continue;
					}
					chosen.add(conn);
				}
				this.goal = chosen.size;
				this.opened = 0;
				if (this.goal == 0) {
					return;
				}
				tools.visible = false;
				this.body.visible_child_name = "run";
				this.title = "executing .... 0/" + this.goal.to_string();
				for (var i = 0; i < chosen.size; i++) {
					var conn = chosen.get(i);
					var term = new Terminal.Ssh(conn, this.main.config);
					var page = tabs.append(term);
					page.title = conn.name;
					var chip = new Gtk.Button.with_label(conn.name);
					chip.add_css_class("flat");
					chip.clicked.connect(() => {
						tabs.selected_page = page;
					});
					strip.append(chip);
					var job = new Jobs.Batch(this.main, conn, term);
					job.run.begin((obj, res) => {
						try {
							job.run.end(res);
						} catch (Jobs.Error e) {
							GLib.warning("batch open failed name=%s: %s",
								conn.name, e.message);
						}
						this.opened++;
						this.title = "executing .... " + this.opened.to_string()
							+ "/" + this.goal.to_string();
						if (this.opened < this.goal) {
							return;
						}
						this.title = "starting...";
						GLib.Timeout.add(10000, () => {
							this.run.label = "Cancel";
							this.run.sensitive = true;
							this.run.remove_css_class("suggested-action");
							this.run.add_css_class("destructive-action");
							return false;
						});
					});
				}
			});
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			header.pack_start(close);
			header.pack_end(this.run);
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			box.append(tools);
			box.append(this.body);
			var toolbar = new Adw.ToolbarView() {
				content = box
			};
			toolbar.add_top_bar(header);
			this.content = toolbar;
			this.map.connect(() => {
				GLib.Idle.add(() => {
					this.main.shell.register(this, "plan");
					return false;
				});
			});
			this.close_request.connect(() => {
				if (this.closing || this.picks.size == 0) {
					this.main.dbus.call_shell_async("hide", new GLib.Variant("(s)", "plan"));
					return false;
				}
				var alert = new Adw.AlertDialog("Are you sure?", null) {
					default_response = "cancel",
					close_response = "cancel"
				};
				alert.add_response("cancel", "Cancel");
				alert.add_response("close", "Close");
				alert.set_response_appearance("close", Adw.ResponseAppearance.DESTRUCTIVE);
				alert.response.connect((response) => {
					if (response != "close") {
						return;
					}
					this.closing = true;
					this.close();
				});
				alert.present(this);
				return true;
			});
			this.search.search_changed.connect(() => {
				this.filter.search = this.search.text;
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
				for (var i = 0; i < this.hosts.size; i++) {
					pending.add(this.hosts.get(i));
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
		 * Insert a draft task for ''script'' and show the host tree.
		 *
		 * @param script command being sent
		 * @param tree host tree
		 */
		public void open(RooTerm.SQT.Script script, Host.TreeNodes tree)
		{
			this.task = new RooTerm.SQT.Task() {
				name = script.path,
				is_script = true,
				command = script.body,
				script_id = script.id,
				is_draft = true
			};
			this.tasks.save(this.task);
			this.hosts = tree;
			this.picks.clear();
			this.closing = false;
			this.title = "Hosts to execute commands";
			if (script.path.strip() != "") {
				this.title = "Hosts to execute '" + script.path.strip() + "'";
			}
			this.refresh_select();
			this.present();
			GLib.Timeout.add(50, () => {
				this.main.dbus.call_shell_async("show", new GLib.Variant("(s)", "plan"));
				return false;
			});
		}

		/**
		 * Select all becomes Select none when every matching row is ticked.
		 */
		private void refresh_select()
		{
			var total = 0;
			var picked = 0;
			var pending = new Gee.ArrayList<Host.Connection>();
			for (var i = 0; i < this.hosts.size; i++) {
				pending.add(this.hosts.get(i));
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
			this.run.sensitive = picked > 0;
			if (this.tree_model.get_n_items() == 0) {
				this.body.visible_child_name = "empty";
				return;
			}
			this.body.visible_child_name = "list";
		}
	}
}
