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

namespace RooTerm.Jobs
{
	/**
	 * Batch SSH open for one planning target.
	 *
	 * Same login as {@link OpenSession}, including sudo when set.
	 * Stops at the shell. Does not run ``lxc-console``.
	 * {@link inject} runs ``lxc-attach`` and the command lines.
	 * The caller already built the terminal.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var job = new Jobs.Batch(window, connection, term);
	 * job.run.begin();
	 * }}}
	 */
	public class Batch : OpenSession
	{
		public RooTerm.SQT.Script script = new RooTerm.SQT.Script();
		public RooTerm.Dialog.Plan plan;
		public RooTerm.SQT.TaskTarget target = new RooTerm.SQT.TaskTarget();
		public RooTerm.Store.TaskTarget targets;
		public Adw.TabPage page;
		public Gtk.Button chip;
		public Gtk.Image tick_icon = new Gtk.Image.from_icon_name("emblem-ok-symbolic");
		public bool halt = false;
		public bool feeding = false;
		public bool tick = false;
		public bool passed = false;
		/**
		 * Cursor row of the command just sent.
		 * That row is still the old prompt.
		 * The next prompt is a later row.
		 */
		private long prompt_row = -1;

		/**
		 * @param window Main window (secrets and login prompts)
		 * @param connection Host or container being opened
		 * @param existing Terminal already shown in the batch window
		 */
		public Batch(RooTerm.MainWindow window, Host.Connection connection, Terminal.Base existing)
		{
			base(window, connection, existing);
			this.targets = new RooTerm.Store.TaskTarget(window.tree.db);
		}

		/**
		 * Password / passphrase prompt, or already at a shell.
		 */
		protected override async void login() throws Error
		{
			if (this.connection.auth == "manual") {
				while (!yield this.expect(State.WAIT_SHELL_PROMPT, 30000)) {
					switch (this.current_state) {
						case State.WAIT_HOST_CONFIRM:
						case State.WAIT_VERIFICATION_CODE:
						case State.WAIT_SSH_PASSWORD:
							continue;

						default:
							throw new Error.TIMEOUT("login shell timeout name=%s".printf(
								this.connection.name));
					}
				}
				return;
			}
			while (!yield this.expect(State.WAIT_SSH_PASSWORD, 30000)) {
				switch (this.current_state) {
					case State.WAIT_SHELL_PROMPT:
						return;

					case State.WAIT_HOST_CONFIRM:
					case State.WAIT_VERIFICATION_CODE:
						continue;

					default:
						throw new Error.TIMEOUT("login password timeout name=%s".printf(
							this.connection.name));
				}
			}
			if (this.connection.passphrase.length > 0) {
				this.terminal.terminal.feed_child((this.connection.passphrase + "\n").data);
			}
			if (this.connection.passphrase.length == 0) {
				this.terminal.terminal.feed_child((this.connection.pass + "\n").data);
			}
			this.current_state = State.UNKNOWN;
			while (!yield this.expect(State.WAIT_SHELL_PROMPT, 30000)) {
				switch (this.current_state) {
					case State.WAIT_VERIFICATION_CODE:
						continue;

					default:
						throw new Error.TIMEOUT("login shell timeout name=%s".printf(
							this.connection.name));
				}
			}
		}

		/**
		 * Spawn, log in, and sudo when that host asks for it.
		 */
		public override async void run() throws Error
		{
			this.terminal.spawn();
			yield this.login();
			if (this.connection.sudo_after_login) {
				yield this.sudo();
			}
			this.current_state = State.DONE;
		}

		/**
		 * Feed {@link RooTerm.SQT.Script.body} after the shell is up.
		 *
		 * An LXC row runs ``lxc-attach`` first. The title then
		 * says ``about to run`` and counts five dots down
		 * to one. Blank lines are
		 * skipped. Each other line is {@link inject_line}. The text
		 * from the last line to that prompt is matched with
		 * {@link RooTerm.SQT.Script.success_regex}.
		 *
		 * Empty ``success_regex`` counts as success and does not tick.
		 * A match ticks and stores ``success`` 0. A miss, a
		 * timeout, or {@link halt} stores a non-zero ``success``.
		 */
		public async void inject() throws Error, GLib.RegexError
		{
			this.tick = false;
			this.passed = false;
			if (this.halt) {
				GLib.debug("inject halt name=%s", this.connection.name);
				this.target.is_cancelled = true;
				this.target.success = 1;
				this.target.ended = (int64) new GLib.DateTime.now_local().to_unix();
				this.targets.save(this.target);
				return;
			}
			if (this.connection.kind == Host.ConnectionKind.LXC) {
				this.current_state = State.UNKNOWN;
				long hold_col, hold_row;
				this.terminal.terminal.get_cursor_position(out hold_col, out hold_row);
				this.prompt_row = hold_row;
				GLib.debug("attach send name=%s lxc=%s row=%ld",
					this.connection.name, this.connection.lxc_name, hold_row);
				this.terminal.terminal.feed_child(
					("lxc-attach -n " + this.connection.lxc_name + "\n").data);
				var attached = yield this.expect(State.WAIT_SHELL_PROMPT, 60000);
				if (!attached && this.current_state != State.WAIT_ROOT_PROMPT) {
					GLib.debug("attach timeout name=%s state=%s",
						this.connection.name, this.current_state.to_string());
					throw new Error.TIMEOUT("lxc attach timeout name=%s".printf(this.connection.name));
				}
				GLib.debug("attach prompt name=%s state=%s",
					this.connection.name, this.current_state.to_string());
			}
			GLib.debug("dots start name=%s", this.connection.name);
			for (var dots = 5; dots > 0; dots--) {
				this.plan.title = "about to run " + string.nfill(dots, '.');
				if (dots == 1) {
					GLib.debug("dots one name=%s", this.connection.name);
					break;
				}
				GLib.Timeout.add(1000, () => {
					this.inject.callback();
					return false;
				});
				yield;
				if (this.halt) {
					GLib.debug("dots halt name=%s", this.connection.name);
					this.target.is_cancelled = true;
					this.target.success = 1;
					this.target.ended = (int64) new GLib.DateTime.now_local().to_unix();
					this.targets.save(this.target);
					return;
				}
			}
			var parts = this.script.body.split("\n");
			GLib.debug("body start name=%s chars=%d parts=%d",
				this.connection.name, this.script.body.length, parts.length);
			var text = "";
			for (var i = 0; i < parts.length; i++) {
				if (this.halt) {
					GLib.debug("body halt name=%s index=%d", this.connection.name, i);
					this.target.is_cancelled = true;
					this.target.success = 1;
					this.target.ended = (int64) new GLib.DateTime.now_local().to_unix();
					this.targets.save(this.target);
					return;
				}
				var line = parts[i].replace("\r", "");
				if (line.strip().length == 0) {
					GLib.debug("body skip blank name=%s index=%d", this.connection.name, i);
					continue;
				}
				text = yield this.inject_line(line);
			}
			GLib.debug("body loop done name=%s identifier=%s",
				this.connection.name, this.target.identifier.to_string());
			this.passed = true;
			this.target.success = 0;
			if (this.script.success_regex.strip().length == 0) {
				this.target.ended = (int64) new GLib.DateTime.now_local().to_unix();
				this.targets.save(this.target);
				this.current_state = State.DONE;
				return;
			}
			this.passed = false;
			this.target.success = 1;
			var check = new GLib.Regex(this.script.success_regex);
			GLib.MatchInfo info;
			if (check.match(text, 0, out info)) {
				this.passed = true;
				this.tick = true;
				this.target.success = 0;
			}
			this.target.ended = (int64) new GLib.DateTime.now_local().to_unix();
			this.targets.save(this.target);
			this.current_state = State.DONE;
		}

		/**
		 * Feed one command line and wait for the shell prompt.
		 *
		 * Bumps {@link RooTerm.SQT.TaskTarget.identifier}. Returns
		 * the text from this line to the next prompt.
		 *
		 * @param line one non-blank line from the script body
		 * @return the terminal text for this line
		 */
		private async string inject_line(string line) throws Error
		{
			long start_col, start_row;
			this.terminal.terminal.get_cursor_position(out start_col, out start_row);
			this.current_state = State.UNKNOWN;
			this.prompt_row = start_row;
			GLib.debug("body line name=%s row=%ld text=%s", this.connection.name, start_row, line);
			this.terminal.terminal.feed_child((line + "\n").data);
			var prompted = yield this.expect(State.WAIT_SHELL_PROMPT, 60000);
			if (!prompted && this.current_state != State.WAIT_ROOT_PROMPT) {
				GLib.debug("body line timeout name=%s state=%s text=%s",
					this.connection.name, this.current_state.to_string(), line);
				throw new Error.TIMEOUT("command timeout name=%s".printf(this.connection.name));
			}
			this.target.identifier++;
			GLib.debug("body line prompt name=%s identifier=%s",
				this.connection.name, this.target.identifier.to_string());
			this.targets.save(this.target);
			long end_col, end_row;
			this.terminal.terminal.get_cursor_position(out end_col, out end_row);
			size_t sample_len;
			var sample = this.terminal.terminal.get_text_range_format(
				Vte.Format.TEXT, start_row, 0, end_row, end_col, out sample_len);
			if (sample == null) {
				return "";
			}
			return sample;
		}

		/**
		 * Skip the prompt on the row we just typed on.
		 * A later row is the next prompt.
		 * A ``#`` prompt stays a root prompt.
		 *
		 * @param cursor_line Non-empty cursor row text
		 */
		protected override void on_content(string cursor_line)
		{
			if (this.prompt_row < 0) {
				base.on_content(cursor_line);
				return;
			}
			long col, row;
			this.terminal.terminal.get_cursor_position(out col, out row);
			if (row <= this.prompt_row) {
				GLib.debug("prompt hold name=%s row=%ld line=%s",
					this.connection.name, row, cursor_line);
				return;
			}
			this.prompt_row = -1;
			GLib.debug("prompt release name=%s row=%ld line=%s",
				this.connection.name, row, cursor_line);
			base.on_content(cursor_line);
		}
	}
}
