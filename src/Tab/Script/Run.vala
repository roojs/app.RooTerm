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
	 * Terminals for one script run inside {@link RooTerm.Dialog.Script}.
	 *
	 * Run on the host picker fills this page. The window title is
	 * ``starting``, then ``about to run``, then ``running``, then
	 * ``completed``. Cancel stays up until the jobs stop.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var run = new RooTerm.Tab.Script.Run(sender);
	 * }}}
	 */
	public class Run : Gtk.Box
	{
		private weak RooTerm.Dialog.Script sender;
		/**
		 * Header Run button. The window packs it on the host picker.
		 */
		public Gtk.Button start_btn;
		/**
		 * Header Cancel button. The window packs it while jobs are going.
		 */
		public Gtk.Button cancel_btn;
		/**
		 * Jobs for the run now on screen.
		 */
		public Gee.ArrayList<Jobs.Batch> jobs {
			get; set; default = new Gee.ArrayList<Jobs.Batch>();
		}
		/**
		 * Bumped when a visit ends or a new run starts.
		 * The countdown from the previous run then stops.
		 */
		public int wave = 0;
		/**
		 * True after Cancel, or after {@link Edit.load} ends the visit.
		 */
		public bool stopped = false;
		/**
		 * True once Cancel has gone and Back can show.
		 */
		public bool done = false;
		private Adw.TabView tabs;
		private Gtk.Box strip;
		private int opened = 0;
		private int goal = 0;
		private int armed = 0;
		private bool counting = false;
		private int finished = 0;
		private int passed = 0;

		/**
		 * @param sender script sender window
		 */
		public Run(RooTerm.Dialog.Script sender)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				hexpand: true,
				vexpand: true
			);
			this.sender = sender;
			this.start_btn = new Gtk.Button.with_label("Run") {
				sensitive = false
			};
			this.start_btn.add_css_class("suggested-action");
			this.cancel_btn = new Gtk.Button.with_label("Cancel");
			this.cancel_btn.add_css_class("destructive-action");
			this.cancel_btn.clicked.connect(() => {
				this.stopped = true;
				this.done = true;
				for (var i = 0; i < this.jobs.size; i++) {
					this.jobs.get(i).halt = true;
					this.jobs.get(i).released = true;
				}
				this.sender.show_page(RooTerm.Dialog.Script.Page.RUN);
			});
			this.tabs = new Adw.TabView() {
				hexpand = true,
				vexpand = true
			};
			this.tabs.add_css_class("vte-host");
			this.strip = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2) {
				hexpand = true
			};
			this.strip.add_css_class("host-tabbar");
			this.add_css_class("vte-path");
			this.append(this.tabs);
			this.append(this.strip);
			this.start_btn.clicked.connect(() => {
				this.sender.hosts.task.is_draft = false;
				this.sender.hosts.tasks.save(this.sender.hosts.task);
				this.start_btn.sensitive = false;
				this.wave++;
				this.stopped = false;
				this.done = false;
				this.counting = false;
				this.armed = 0;
				this.finished = 0;
				this.passed = 0;
				this.opened = 0;
				for (var i = 0; i < this.jobs.size; i++) {
					this.jobs.get(i).halt = true;
					this.jobs.get(i).released = true;
					var pid = this.jobs.get(i).terminal.child_pid;
					if (pid > 0) {
						Posix.kill(pid, Posix.Signal.TERM);
					}
				}
				this.jobs.clear();
				while (this.tabs.n_pages > 0) {
					var before = this.tabs.n_pages;
					this.tabs.close_page(this.tabs.get_nth_page(0));
					if (this.tabs.n_pages >= before) {
						break;
					}
				}
				var child = this.strip.get_first_child();
				while (child != null) {
					var next = child.get_next_sibling();
					this.strip.remove(child);
					child = next;
				}
				var chosen = new Gee.ArrayList<Host.Connection>();
				var pending = new Gee.ArrayList<Host.Connection>();
				for (var i = 0; i < this.sender.hosts.nodes.size; i++) {
					pending.add(this.sender.hosts.nodes.get(i));
				}
				var at = 0;
				while (at < pending.size) {
					var conn = pending.get(at);
					at++;
					for (var i = 0; i < conn.children.size; i++) {
						pending.add(conn.children.get(i));
					}
					if (!this.sender.hosts.picks.has_key((int) conn.id)) {
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
				if (this.goal == 0) {
					this.sender.hosts.refresh_select();
					return;
				}
				this.sender.show_page(RooTerm.Dialog.Script.Page.RUN);
				this.sender.title = "starting %d/%d".printf(0, this.goal);
				for (var i = 0; i < chosen.size; i++) {
					this.append_job(chosen.get(i));
				}
				this.goal = this.jobs.size;
				this.sender.title = "starting %d/%d".printf(0, this.goal);
				if (this.tabs.n_pages > 0) {
					this.tabs.selected_page = this.tabs.get_nth_page(0);
				}
			});
		}

		/**
		 * Open one ticked host and keep the job on {@link jobs}.
		 *
		 * @param conn host or container to run
		 */
		private void append_job(Host.Connection conn)
		{
			var rows = new Gee.ArrayList<RooTerm.SQT.TaskTarget>();
			RooTerm.SQT.TaskTarget.query(this.sender.main.tree.db).select(
				"WHERE id = " + this.sender.hosts.picks.get((int) conn.id).to_string(),
				rows);
			if (rows.size == 0) {
				return;
			}
			var target = rows.get(0);
			target.started = (int64) new GLib.DateTime.now_local().to_unix();
			this.sender.hosts.targets.save(target);
			var term = new Terminal.Ssh(conn, this.sender.main.config);
			var shown = this.sender.main.sessions.stack.pages.visible_child as Host.Page;
			if (shown != null && shown.current != null) {
				term.terminal.font_desc = shown.current.terminal.font_desc;
				term.terminal.font_scale = shown.current.terminal.font_scale;
			}
			GLib.debug("batch font name=%s font=%s scale=%s",
				conn.name, term.terminal.font_desc.to_string(), term.terminal.font_scale.to_string());
			var page = this.tabs.append(term);
			page.title = conn.name;
			var tick_icon = new Gtk.Image.from_icon_name("object-select-symbolic") {
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
				this.tabs.selected_page = page;
			});
			this.strip.append(chip);
			var job = new Jobs.Batch(this.sender.main, conn, term) {
				script = this.sender.hosts.script,
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
					this.sender.hosts.targets.save(target);
					this.finish(job);
					return;
				}
				this.opened++;
				if (!this.counting) {
					this.sender.title = "starting %d/%d".printf(this.opened, this.goal);
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
					this.sender.hosts.targets.save(job.target);
				}
				this.finish(job);
			});
		}

		/**
		 * One shared countdown, after every target has attached
		 * or failed login.
		 *
		 * ``waiting`` means this call is a target that has attached.
		 * The title stays on ``starting`` until then, then
		 * ``about to run`` for three seconds, then ``running``.
		 * ``completed`` is only when every target has finished.
		 *
		 * @param waiting true when a target is ready for the body
		 */
		public void sync_title(bool waiting)
		{
			if (waiting) {
				this.armed++;
			}
			if (this.counting || this.finished == this.goal) {
				return;
			}
			if (this.armed + this.finished < this.goal) {
				return;
			}
			this.counting = true;
			var dots = 3;
			var wave = this.wave;
			this.sender.title = "about to run " + string.nfill(dots, '.');
			GLib.debug("countdown start goal=%d", this.goal);
			GLib.Timeout.add(1000, () => {
				if (wave != this.wave) {
					return false;
				}
				if (this.stopped) {
					for (var i = 0; i < this.jobs.size; i++) {
						this.jobs.get(i).released = true;
					}
					return false;
				}
				dots--;
				if (dots < 1) {
					GLib.debug("countdown release goal=%d", this.goal);
					for (var i = 0; i < this.jobs.size; i++) {
						this.jobs.get(i).released = true;
					}
					this.sender.title = "running";
					return false;
				}
				this.sender.title = "about to run " + string.nfill(dots, '.');
				return true;
			});
		}

		/**
		 * One target has finished. Update the tick.
		 *
		 * The title stays put until every target has finished.
		 * Then it is ``completed 8/10``, or with success
		 * counts when criteria is set.
		 * The last finish sets ``task.completed``.
		 *
		 * @param job machine that just finished
		 */
		private void finish(Jobs.Batch job)
		{
			if (!this.jobs.contains(job)) {
				return;
			}
			this.finished++;
			if (job.passed) {
				this.passed++;
			}
			if (job.tick) {
				job.tick_icon.visible = true;
				var id = (int) job.connection.id;
				if (this.sender.hosts.picks.has_key(id)) {
					var target = new RooTerm.SQT.TaskTarget() {
						id = this.sender.hosts.picks.get(id)
					};
					this.sender.hosts.targets.remove(target);
					this.sender.hosts.picks.unset(id);
					this.sender.hosts.picks_changed();
					this.sender.hosts.refresh_select();
				}
			}
			if (this.finished < this.goal) {
				this.sync_title(false);
				return;
			}
			if (this.sender.hosts.script.success_regex.strip().length == 0) {
				this.sender.title = "completed %d/%d".printf(this.finished, this.goal);
			}
			if (this.sender.hosts.script.success_regex.strip().length > 0) {
				this.sender.title = "completed %d/%d - success %d/%d".printf(
					this.finished,
					this.goal,
					this.passed,
					this.goal
				);
			}
			this.done = true;
			this.sender.hosts.task.completed = (int64) new GLib.DateTime.now_local().to_unix();
			this.sender.hosts.tasks.save(this.sender.hosts.task);
			this.sender.show_page(RooTerm.Dialog.Script.Page.RUN);
		}
	}
}
