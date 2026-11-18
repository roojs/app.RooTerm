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
		private Gtk.Button cancel;
		private Gtk.Button dismiss;
		private Adw.ToggleGroup scopes;
		private Gtk.Stack body;
		private int opened = 0;
		private int goal = 0;
		private bool closing = false;
		private bool stopped = false;
		private RooTerm.SQT.Script script {
			get; set; default = new RooTerm.SQT.Script();
		}
		private bool sending = false;
		private int finished = 0;
		private int passed = 0;
		private Gee.ArrayList<Jobs.Batch> jobs {
			get; set; default = new Gee.ArrayList<Jobs.Batch>();
		}

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
				default_width: 1008,
				default_height: 728
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
			tabs.add_css_class("vte-host");
			var strip = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2) {
				hexpand = true
			};
			strip.add_css_class("host-tabbar");
			var running = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			running.add_css_class("vte-path");
			running.append(tabs);
			running.append(strip);
			this.body.add_named(running, "run");
			this.dismiss = new Gtk.Button.with_label("Close");
			this.dismiss.clicked.connect(() => {
				if (this.jobs.size > 0) {
					this.closing = true;
				}
				this.close();
			});
			this.cancel = new Gtk.Button.with_label("Cancel") {
				visible = false
			};
			this.cancel.add_css_class("destructive-action");
			this.cancel.clicked.connect(() => {
				this.stopped = true;
				for (var i = 0; i < this.jobs.size; i++) {
					this.jobs.get(i).halt = true;
				}
				this.cancel.visible = false;
				this.dismiss.visible = true;
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
				this.task.is_draft = false;
				this.tasks.save(this.task);
				this.run.sensitive = false;
				this.stopped = false;
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
				this.cancel.visible = true;
				this.dismiss.visible = false;
				tools.visible = false;
				this.body.visible_child_name = "run";
				this.title = "executing .... %d/%d".printf(0, this.goal);
				for (var i = 0; i < chosen.size; i++) {
					this.append_job(chosen.get(i), tabs, strip);
				}
				this.goal = this.jobs.size;
				this.title = "executing .... %d/%d".printf(0, this.goal);
			});
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			header.pack_start(this.run);
			header.pack_end(this.dismiss);
			header.pack_end(this.cancel);
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
				if (this.cancel.visible) {
					return true;
				}
				if (this.closing || this.picks.size == 0) {
					for (var i = 0; i < this.jobs.size; i++) {
						var pid = this.jobs.get(i).terminal.child_pid;
						if (pid < 1) {
							continue;
						}
						Posix.kill(pid, Posix.Signal.TERM);
					}
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
			this.script = script;
			this.task = new RooTerm.SQT.Task() {
				is_script = true,
				script_id = script.id,
				is_draft = true
			};
			this.tasks.save(this.task);
			this.hosts = tree;
			this.picks.clear();
			this.closing = false;
			this.sending = false;
			this.finished = 0;
			this.passed = 0;
			this.opened = 0;
			this.jobs.clear();
			this.cancel.visible = false;
			this.dismiss.visible = true;
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
		 * Open one ticked host and keep the job on {@link jobs}.
		 *
		 * @param conn host or container to run
		 * @param tabs terminal pages in this window
		 * @param strip tab buttons along the bottom
		 */
		private void append_job(Host.Connection conn, Adw.TabView tabs, Gtk.Box strip)
		{
			var rows = new Gee.ArrayList<RooTerm.SQT.TaskTarget>();
			RooTerm.SQT.TaskTarget.query(this.main.tree.db).select(
				"WHERE id = " + this.picks.get((int) conn.id).to_string(),
				rows);
			if (rows.size == 0) {
				return;
			}
			var target = rows.get(0);
			target.started = (int64) new GLib.DateTime.now_local().to_unix();
			this.targets.save(target);
			var term = new Terminal.Ssh(conn, this.main.config);
			var shown = this.main.sessions.stack.pages.visible_child as Host.Page;
			if (shown != null && shown.current != null) {
				term.terminal.font_desc = shown.current.terminal.font_desc;
				term.terminal.font_scale = shown.current.terminal.font_scale;
			}
			GLib.debug("batch font name=%s font=%s scale=%s",
				conn.name, term.terminal.font_desc.to_string(), term.terminal.font_scale.to_string());
			var page = tabs.append(term);
			page.title = conn.name;
			var tick_icon = new Gtk.Image.from_icon_name("emblem-ok-symbolic") {
				visible = false
			};
			var chip_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			chip_box.append(new Gtk.Label(conn.name));
			chip_box.append(tick_icon);
			var chip = new Gtk.Button() {
				child = chip_box,
				tooltip_text = conn.name
			};
			chip.add_css_class("flat");
			chip.clicked.connect(() => {
				tabs.selected_page = page;
			});
			strip.append(chip);
			var job = new Jobs.Batch(this.main, conn, term) {
				script = this.script,
				target = target,
				page = page,
				chip = chip,
				tick_icon = tick_icon,
				plan = this
			};
			this.jobs.add(job);
			job.run.begin((obj, res) => {
				try {
					job.run.end(res);
				} catch (Jobs.Error e) {
					GLib.warning("batch open failed name=%s: %s", conn.name, e.message);
					target.ended = (int64) new GLib.DateTime.now_local().to_unix();
					target.success = 1;
					this.targets.save(target);
					this.finish(job);
					return;
				}
				this.opened++;
				if (this.finished == 0 && !this.sending) {
					this.title = "executing .... %d/%d".printf(this.opened, this.goal);
				}
				GLib.debug("shell up name=%s kind=%s", conn.name, conn.kind.to_string());
				this.feed(job);
			});
		}

		/**
		 * Start {@link Jobs.Batch.inject} once this shell is up.
		 *
		 * A stopped run, a job already feeding, or a shell that is
		 * not up yet does nothing.
		 *
		 * @param job batch login for one machine
		 */
		private void feed(Jobs.Batch job)
		{
			if (this.stopped || job.feeding) {
				GLib.debug("feed skip name=%s stopped=%d feeding=%d",
					job.connection.name, this.stopped ? 1 : 0, job.feeding ? 1 : 0);
				return;
			}
			if (job.current_state != Jobs.Job.State.DONE) {
				GLib.debug("feed skip name=%s state=%s",
					job.connection.name, job.current_state.to_string());
				return;
			}
			GLib.debug("feed name=%s", job.connection.name);
			job.feeding = true;
			job.inject.begin((obj, res) => {
				try {
					job.inject.end(res);
				} catch (GLib.Error e) {
					GLib.warning("batch inject failed name=%s: %s", job.connection.name, e.message);
					job.passed = false;
					job.tick = false;
					job.target.ended = (int64) new GLib.DateTime.now_local().to_unix();
					job.target.success = 1;
					this.targets.save(job.target);
				}
				this.finish(job);
			});
		}

		/**
		 * One target has finished. Update the title and the tick.
		 *
		 * The title is ``completed 8/10 - success 4/10``.
		 * Finished out of selected, then passed out of selected.
		 * The last finish sets ``task.completed``.
		 *
		 * @param job machine that just finished
		 */
		private void finish(Jobs.Batch job)
		{
			this.finished++;
			if (job.passed) {
				this.passed++;
			}
			if (job.tick) {
				job.tick_icon.visible = true;
			}
			if (this.script.success_regex.strip().length == 0) {
				this.title = "completed %d/%d".printf(this.finished, this.goal);
			}
			if (this.script.success_regex.strip().length > 0) {
				this.title = "completed %d/%d - success %d/%d".printf(
					this.finished,
					this.goal,
					this.passed,
					this.goal
				);
			}
			if (this.finished < this.goal) {
				return;
			}
			this.cancel.visible = false;
			this.dismiss.visible = true;
			this.task.completed = (int64) new GLib.DateTime.now_local().to_unix();
			this.tasks.save(this.task);
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
