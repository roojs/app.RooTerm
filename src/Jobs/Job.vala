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
	 * Stop conditions for {@link Job.expect} / {@link Job.run}.
	 */
	public errordomain JobError
	{
		TIMEOUT,
		CANCEL,
		FAIL
	}

	/**
	 * Base for ConnDialog terminal jobs.
	 *
	 * Ctor takes {@link window} + {@link connection}, creates the helper tab via
	 * {@link SessionController.create} (no spawn), and exposes the live
	 * {@link stream} so subclass ctors can set flags / connect signals.
	 * Subclass {@link run} calls {@link Terminal.spawn} then the yield flow.
	 * {@link dispose} closes the tab.
	 */
	public abstract class Job : Object
	{
		/**
		 * Job / terminal situation. {@link want} and {@link current_state} share this enum.
		 *
		 * Waits = prompts / UI we may park on. Conclusions = outcomes already reached
		 * (success or error). Error conclusions make {@link expect} throw {@link JobError}.
		 */
		public enum State
		{
			UNKNOWN,
			// --- waits (prompts / UI) ---
			WAIT_KEY_DIALOG,
			WAIT_ALERT,
			WAIT_SSH_PASSWORD,
			WAIT_SHELL_PROMPT,
			WAIT_SUDO_PASSWORD,
			WAIT_ROOT_PROMPT,
			WAIT_COMMAND_OUTPUT,
			// --- success conclusions ---
			KEY_INSTALLED,
			KEY_RETIRED,
			CONTAINERS_FOUND,
			DONE,
			// --- error conclusions ---
			FAILED,
			CANCELLED,
			TIMEOUT
		}

		/**
		 * Main window (sessions / dialogs).
		 */
		public MainWindow window { get; construct; }

		/**
		 * Host the job acts on.
		 */
		public Connection connection { get; construct; }

		/**
		 * SSH stream for the helper tab — set in the ctor after
		 * {@link SessionController.create}. Subclass ctors set flags / connect
		 * signals; {@link run} spawns.
		 */
		public SshStream stream;

		/**
		 * Helper tab — VTE is ``terminal.terminal``.
		 */
		public Terminal terminal;

		/**
		 * What the current {@link expect} is hoping to see.
		 */
		public State want = State.UNKNOWN;

		/**
		 * What the VTE (or UI) looks like right now — set by {@link on_content}.
		 */
		public State current_state = State.UNKNOWN;

		/**
		 * When true, {@link dispose} unwires but does not close the tab.
		 */
		public bool keep_open = false;

		private ulong contents_changed_id = 0;
		private uint content_debounce = 0;
		private ulong close_tab_id = 0;

		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 */
		protected Job(MainWindow window, Connection connection)
		{
			Object(window: window, connection: connection);
			this.terminal = this.window.sessions.create(this.connection);
			var ssh = this.terminal as SshTerminal;
			this.stream = ssh.stream;
			this.contents_changed_id = this.terminal.terminal.contents_changed.connect(() => {
				if (this.content_debounce != 0) {
					return;
				}
				this.content_debounce = GLib.Timeout.add(120, () => {
					this.content_debounce = 0;
					long col, row;
					this.terminal.terminal.get_cursor_position(out col, out row);
					size_t line_len;
					var raw_line = this.terminal.terminal.get_text_range_format(
						Vte.Format.TEXT, row, 0, row, col, out line_len
					);
					var cursor_line = raw_line != null ? raw_line.replace("\r", "").strip() : "";
					if (cursor_line.length == 0 || cursor_line.length > 240) {
						return false;
					}
					this.on_content(cursor_line);
					return false;
				});
			});
			this.close_tab_id = this.terminal.close_tab.connect(() => {
				if (this.current_state != State.CANCELLED && this.current_state != State.DONE) {
					this.current_state = State.CANCELLED;
				}
			});
		}

		public override void dispose()
		{
			if (this.content_debounce != 0) {
				GLib.Source.remove(this.content_debounce);
				this.content_debounce = 0;
			}
			if (this.contents_changed_id != 0 && this.terminal != null) {
				this.terminal.terminal.disconnect(this.contents_changed_id);
				this.contents_changed_id = 0;
			}
			if (this.close_tab_id != 0 && this.terminal != null) {
				this.terminal.disconnect(this.close_tab_id);
				this.close_tab_id = 0;
			}
			if (this.terminal != null) {
				if (!this.keep_open) {
					this.terminal.close_tab();
				}
				this.terminal = null;
			}
			base.dispose();
		}

		/**
		 * Subclass yield flow.
		 */
		public abstract async void run() throws JobError;

		/**
		 * Classify the cursor line → {@link current_state}. Override in the job that
		 * owns the prompt; call ``base.on_content`` for parent checks.
		 *
		 * @param cursor_line Non-empty cursor row text (no ``\\r``; length already capped)
		 */
		protected virtual void on_content(string cursor_line)
		{
		}

		/**
		 * Park until {@link current_state} equals {@link want_state}, else throw.
		 *
		 * @param want_state Prompt or conclusion we are waiting to see
		 * @param timeout_ms Deadline → sets {@link State.TIMEOUT}
		 */
		protected async void expect(State want_state, uint timeout_ms) throws JobError
		{
			this.want = want_state;
			GLib.debug("job expect name=%s want=%d timeout_ms=%u current_state=%d",
				this.connection.name, (int) want_state, timeout_ms, (int) this.current_state);
			if (this.current_state == want_state) {
				return;
			}
			switch (this.current_state) {
				case State.CANCELLED:
					throw new JobError.CANCEL("job cancelled name=%s".printf(this.connection.name));
				case State.FAILED:
					throw new JobError.FAIL("terminal failure name=%s want=%d".printf(
						this.connection.name, (int) want_state));
				case State.TIMEOUT:
					throw new JobError.TIMEOUT("expect timeout want=%d name=%s".printf(
						(int) want_state, this.connection.name));
			}

			var resumed = false;

			ulong notify_state = this.notify["current_state"].connect(() => {
				if (resumed) {
					return;
				}
				if (this.current_state == want_state) {
					resumed = true;
					expect.callback();
					return;
				}
				switch (this.current_state) {
					case State.FAILED:
					case State.CANCELLED:
					case State.TIMEOUT:
						resumed = true;
						expect.callback();
						break;
				}
			});
			uint timeout_id = GLib.Timeout.add(timeout_ms, () => {
				if (resumed) {
					return false;
				}
				this.current_state = State.TIMEOUT;
				return false;
			});

			yield;

			this.disconnect(notify_state);
			GLib.Source.remove(timeout_id);

			if (this.current_state == want_state) {
				return;
			}
			switch (this.current_state) {
				case State.CANCELLED:
					throw new JobError.CANCEL("job cancelled name=%s".printf(this.connection.name));
				case State.FAILED:
					throw new JobError.FAIL("terminal failure name=%s want=%d".printf(
						this.connection.name, (int) want_state));
				case State.TIMEOUT:
					throw new JobError.TIMEOUT("expect timeout want=%d name=%s".printf(
						(int) want_state, this.connection.name));
			}
		}
	}
}
