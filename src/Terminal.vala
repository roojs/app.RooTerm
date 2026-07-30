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
	 * Shared VTE tab chrome for {@link SshTerminal} and {@link LocalTerminal}.
	 * Host pages hold this type; subclasses own spawn / exit behaviour.
	 */
	public abstract class Terminal : Gtk.Box
	{
		public Connection connection;
		public Vte.Terminal terminal;
		/**
		 * Live cwd from OSC 7 when the shell reports it.
		 */
		public string cwd = "";
		/**
		 * Mark for the host-tree session icon (active look is {@link tree_active}).
		 */
		public SessionState state {
			get { return this._state; }
			set {
				if (this._state == value) {
					return;
				}
				this._state = value;
				this.notify_property("state");
				this.notify_property("session-css");
				this.state_changed();
			}
		}
		private SessionState _state = SessionState.IDLE;
		/**
		 * True when this tab is the selected one on its host (tree mark emphasis).
		 */
		public bool tree_active {
			get { return this._tree_active; }
			set {
				if (this._tree_active == value) {
					return;
				}
				this._tree_active = value;
				this.notify_property("tree-active");
				this.notify_property("session-css");
			}
		}
		private bool _tree_active = false;
		/**
		 * CSS modifier for the tree session icon (``session-active`` / idle / busy / …).
		 */
		public string session_css {
			owned get {
				if (this.tree_active) {
					return "session-active";
				}
				switch (this.state) {
					case SessionState.BUSY:
						return "session-busy";

					case SessionState.READY:
						return "session-ready";

					case SessionState.EXITED:
						return "session-exited";

					default:
						return "session-idle";
				}
			}
		}
		/**
		 * Whether this tab is the focused one on its host page.
		 */
		public bool selected = true;
		protected uint settle_timeout = 0;
		private uint close_tick = 0;
		private int close_left = 0;
		private int close_total = 0;
		protected bool close_paused = false;
		protected bool close_armed = false;
		/**
		 * True when the tab may be removed (countdown finished or Close now).
		 * Tab X starts a countdown until this is set.
		 */
		public bool close_confirmed = false;
		private Gtk.Box close_bar;
		private Gtk.ProgressBar close_progress;

		/**
		 * Emitted when the tab should be closed (exit / countdown).
		 */
		public signal void close_tab();

		/**
		 * Emitted when {@link label} should refresh.
		 */
		public signal void label_changed();

		/**
		 * Emitted when {@link state} changes (busy / ready / idle / exited).
		 */
		public signal void state_changed();

		/**
		 * Build scrolled VTE with copy/paste shortcuts, OSC 7 cwd, and busy/ready marks.
		 *
		 * @param connection Host or Localhost this tab belongs to
		 * @param font Pango font string
		 */
		protected Terminal(Connection connection, string font = "Monospace 9")
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
			this.connection = connection;
			this.terminal = new Vte.Terminal() {
				hexpand = true,
				vexpand = true,
				font_desc = Pango.FontDescription.from_string(font)
			};
			this.terminal.set_size(80, 24);
			this.append(new Gtk.ScrolledWindow() {
				child = this.terminal,
				hexpand = true,
				vexpand = true
			});

			this.close_progress = new Gtk.ProgressBar() {
				fraction = 1.0,
				hexpand = true,
				valign = Gtk.Align.CENTER,
				show_text = true,
				text = ""
			};
			var close_now = new Gtk.Button.with_label("Close now") {
				valign = Gtk.Align.CENTER
			};
			close_now.add_css_class("destructive-action");
			close_now.clicked.connect(() => {
				this.close_in(0);
			});
			var leave_open = new Gtk.Button.with_label("Leave open") {
				valign = Gtk.Align.CENTER,
				tooltip_text = "Enter to reconnect"
			};
			leave_open.add_css_class("suggested-action");
			leave_open.clicked.connect(() => {
				this.cancel_close();
				if (this.state != SessionState.EXITED) {
					return;
				}
				this.terminal.feed("\r\n[Leave open - Enter to reconnect]\r\n".data);
			});
			this.close_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				visible = false,
				margin_start = 8,
				margin_end = 8,
				margin_top = 4,
				margin_bottom = 6
			};
			this.close_bar.append(close_now);
			this.close_bar.append(this.close_progress);
			this.close_bar.append(leave_open);
			this.append(this.close_bar);

			var shortcuts = new Gtk.ShortcutController() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
				scope = Gtk.ShortcutScope.LOCAL
			};
			shortcuts.add_shortcut(new Gtk.Shortcut(
				Gtk.ShortcutTrigger.parse_string("<Control><Shift>c"),
				new Gtk.CallbackAction(() => {
					this.terminal.copy_clipboard_format(Vte.Format.TEXT);
					return true;
				})
			));
			shortcuts.add_shortcut(new Gtk.Shortcut(
				Gtk.ShortcutTrigger.parse_string("<Control><Shift>v"),
				new Gtk.CallbackAction(() => {
					this.terminal.paste_clipboard();
					return true;
				})
			));
			this.terminal.add_controller(shortcuts);

			this.terminal.termprop_changed.connect((prop) => {
				if (prop != Vte.TERMPROP_CURRENT_DIRECTORY_URI) {
					return;
				}
				var uri = this.terminal.ref_termprop_uri(prop);
				if (uri == null) {
					return;
				}
				// Prefer Uri path: File.get_path() is null for file://hostname/...
				var path = uri.get_path();
				if (path == null || path.length == 0) {
					path = GLib.File.new_for_uri(uri.to_string()).get_path();
				}
				if (path == null || path.length == 0) {
					return;
				}
				var unesc = GLib.Uri.unescape_string(path);
				this.cwd = unesc != null ? unesc : path;
				this.label_changed();
			});
			this.terminal.contents_changed.connect(() => {
				if (this.selected || this.state == SessionState.EXITED) {
					return;
				}
				if (this.settle_timeout != 0) {
					GLib.Source.remove(this.settle_timeout);
					this.settle_timeout = 0;
				}
				if (this.state != SessionState.BUSY) {
					this.state = SessionState.BUSY;
				}
				this.settle_timeout = GLib.Timeout.add(1500, () => {
					this.settle_timeout = 0;
					if (this.selected || this.state != SessionState.BUSY) {
						return false;
					}
					this.state = SessionState.READY;
					return false;
				});
			});
		}

		/**
		 * Mark this tab selected on the visible host page (clears busy/ready).
		 *
		 * @param on true when this tab is the focused one
		 */
		public virtual void select(bool on)
		{
			if (this.selected == on) {
				return;
			}
			this.selected = on;
			if (this.settle_timeout != 0) {
				GLib.Source.remove(this.settle_timeout);
				this.settle_timeout = 0;
			}
			if (this.state == SessionState.IDLE) {
				return;
			}
			this.state = SessionState.IDLE;
		}

		/**
		 * Close this tab after ``seconds`` (``0`` = immediately). Callers own the
		 * policy; shared 1s countdown — subclasses refresh chrome via
		 * {@link close_countdown}.
		 *
		 * @param seconds Delay before {@link close_tab}; ``0`` closes now
		 */
		public void close_in(int seconds)
		{
			if (seconds <= 0) {
				if (this.close_tick != 0) {
					GLib.Source.remove(this.close_tick);
					this.close_tick = 0;
				}
				this.close_armed = false;
				this.close_paused = false;
				this.close_countdown(0, this.close_total);
				this.close_confirmed = true;
				this.close_tab();
				return;
			}
			if (this.close_armed || this.close_paused) {
				return;
			}
			this.close_armed = true;
			this.close_left = seconds;
			this.close_total = seconds;
			this.close_countdown(this.close_left, this.close_total);
			if (this.close_tick != 0) {
				GLib.Source.remove(this.close_tick);
			}
			this.close_tick = GLib.Timeout.add_seconds(1, () => {
				if (this.close_paused) {
					this.close_tick = 0;
					return false;
				}
				this.close_left--;
				if (this.close_left <= 0) {
					this.close_tick = 0;
					this.close_countdown(0, this.close_total);
					this.close_confirmed = true;
					this.close_tab();
					return false;
				}
				this.close_countdown(this.close_left, this.close_total);
				return true;
			});
		}

		/**
		 * Stop the close countdown and hide chrome. ``keep_open`` blocks another
		 * {@link close_in} (unused by Leave open — that resets fully so X can
		 * start the countdown again).
		 *
		 * @param keep_open true = block another close_in; false = full reset
		 */
		public void cancel_close(bool keep_open = false)
		{
			if (this.close_tick != 0) {
				GLib.Source.remove(this.close_tick);
				this.close_tick = 0;
			}
			this.close_paused = keep_open;
			if (!keep_open) {
				this.close_armed = false;
				this.close_confirmed = false;
			}
			this.close_countdown(keep_open ? this.close_left : 0, this.close_total);
		}

		/**
		 * Update close chrome each second. ``left == 0`` means hide / done.
		 *
		 * @param left Seconds remaining
		 * @param total Original delay from {@link close_in}
		 */
		protected virtual void close_countdown(int left, int total)
		{
			if (left <= 0 || total <= 0) {
				this.close_bar.visible = false;
				return;
			}
			if (!this.close_bar.visible) {
				this.close_bar.visible = true;
				this.terminal.grab_focus();
			}
			if (this.close_paused) {
				return;
			}
			this.close_progress.text = "Closing in " + left.to_string() + " seconds…";
			this.close_progress.fraction = (double) left / (double) total;
		}

		/**
		 * Tab / tree / window title string for this session.
		 *
		 * @return Display string
		 */
		public abstract string label();

		/**
		 * Start the child process (SSH or local shell).
		 */
		public abstract void spawn();
	}
}
