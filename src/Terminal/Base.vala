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

namespace RooTerm.Terminal
{
	/**
	 * Shared VTE tab chrome for {@link Ssh} and {@link Local}.
	 * Host pages hold this type; subclasses own spawn / exit behaviour.
	 */
	public abstract class Base : Gtk.Box
	{
		public Host.Connection connection;
		public Vte.Terminal terminal;
		/**
		 * VTE commit / contents / cwd watcher for this tab.
		 */
		public Stream stream;
		/**
		 * Last theme colours (``config.opacity`` updates ``theme_bg.alpha``).
		 */
		public Gdk.RGBA theme_fg;
		public Gdk.RGBA theme_bg;
		public Gdk.RGBA[] theme_palette;
		/**
		 * Extra display CSS provider for live ``.vte-frame`` opacity (not the main
		 * ``style.css`` provider in {@link RooTerm.MainWindow}). Gresource CSS cannot take
		 * runtime {@link RooTerm.Config.opacity}; this shared provider is reloaded with an
		 * ``rgba(...)`` rule when opacity changes. Static so every tab shares one.
		 */
		private static Gtk.CssProvider frame_css = new Gtk.CssProvider();
		private static bool frame_css_added = false;
		/**
		 * Child pid from the last successful {@link spawn} (``-1`` if none).
		 */
		public int child_pid = -1;
		/**
		 * Live cwd from OSC 7 / stream when known.
		 */
		public string cwd = "";
		/**
		 * Mark for the host-tree session icon (active look is {@link tree_active}).
		 */
		public Session.State state {
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
		private Session.State _state = Session.State.IDLE;
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
					case Session.State.BUSY:
						return "session-busy";

					case Session.State.READY:
						return "session-ready";

					case Session.State.EXITED:
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
		 * Close countdown tick for tab chrome (``left == 0`` = cancelled / done).
		 *
		 * @param left Milliseconds remaining
		 * @param total Original delay in milliseconds
		 */
		public signal void closing(int left, int total);

		/**
		 * Emitted when {@link label} should refresh.
		 */
		public signal void label_changed();

		/**
		 * Emitted when {@link state} changes (busy / ready / idle / exited).
		 */
		public signal void state_changed();

		/**
		 * Build scrolled VTE with copy/paste shortcuts and busy/ready marks.
		 * Cwd / prompt watching is {@link Stream} (created by subclasses).
		 *
		 * @param connection Host or Localhost this tab belongs to
		 * @param config App config (binds VTE background / theme / font)
		 */
		protected Base(Host.Connection connection, RooTerm.Config config)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
			this.connection = connection;
			this.terminal = new Vte.Terminal() {
				hexpand = true,
				vexpand = true,
				font_desc = config.font_desc()
			};
			this.terminal.set_size(80, 24);
			config.themes.load();
			this.theme_fg = Gdk.RGBA();
			this.theme_bg = Gdk.RGBA();
			/*
			 * VTE does not composite background alpha to the desktop. Below 100%
			 * leave VTE unfilled and paint the dimmed colour on ``.vte-frame``.
			 */
			if (!frame_css_added) {
				Gtk.StyleContext.add_provider_for_display(
					Gdk.Display.get_default(),
					frame_css,
					Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
				);
				frame_css_added = true;
			}
			config.notify.connect((s, pspec) => {
				if (pspec.get_name() == "font-family" || pspec.get_name() == "font-size") {
					this.terminal.font_desc = config.font_desc();
					return;
				}
				if (pspec.get_name() != "opacity"
						&& pspec.get_name() != "theme-name"
						&& pspec.get_name() != "theme-category") {
					return;
				}
				var pick = config.themes.items.get(0);
				var map_key = config.theme_category + "\n" + config.theme_name;
				if (config.themes.by_key.has_key(map_key)) {
					pick = config.themes.by_key.get(map_key);
				}
				this.theme_fg.parse(pick.foreground);
				this.theme_bg.parse(pick.background);
				this.theme_bg.alpha = config.opacity / 100.0f;
				var slots = pick.palette.split(";");
				this.theme_palette = new Gdk.RGBA[slots.length];
				for (var i = 0; i < slots.length; i++) {
					this.theme_palette[i].parse(slots[i]);
				}
				this.terminal.set_colors(this.theme_fg, this.theme_bg, this.theme_palette);
				this.terminal.set_clear_background(config.opacity >= 100);
				if (config.opacity >= 100) {
					frame_css.load_from_string(".vte-frame { background-color: transparent; }");
					return;
				}
				frame_css.load_from_string(
					".vte-frame { background-color: rgba(%u,%u,%u,%.3f); }".printf(
						(uint) (this.theme_bg.red * 255.0f + 0.5f),
						(uint) (this.theme_bg.green * 255.0f + 0.5f),
						(uint) (this.theme_bg.blue * 255.0f + 0.5f),
						config.opacity / 100.0
					)
				);
			});
			config.notify_property("theme-name");
			var vte_frame = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			vte_frame.add_css_class("vte-frame");
			vte_frame.append(this.terminal);
			this.append(vte_frame);

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
				if (this.state != Session.State.EXITED) {
					return;
				}
				this.terminal.feed("\r\n[Leave open - Enter to reconnect]\r\n".data);
			});
			this.close_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				visible = false
			};
			this.close_bar.add_css_class("close-bar");
			this.close_bar.append(close_now);
			this.close_bar.append(this.close_progress);
			this.close_bar.append(leave_open);
			this.append(this.close_bar);

			// mouse zoom
			var zoom = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.VERTICAL
				| Gtk.EventControllerScrollFlags.DISCRETE
			) {
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			zoom.scroll.connect((dx, dy) => {
				var mods = zoom.get_current_event_state();
				if ((mods & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK))
						!= (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
					return false;
				}
				this.terminal.font_scale = dy < 0
					? this.terminal.font_scale * 1.1
					: (dy > 0 ? this.terminal.font_scale / 1.1 : this.terminal.font_scale);
				return true;
			});
			this.terminal.add_controller(zoom);

			var menu_click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY
			};
			menu_click.pressed.connect((n_press, x, y) => {
				var window = this.get_root() as RooTerm.MainWindow;
				if (window == null) {
					return;
				}
				window.terminal_menu.popup_for(this, x, y);
			});
			this.terminal.add_controller(menu_click);

			this.terminal.contents_changed.connect(() => {
				if (this.selected || this.state == Session.State.EXITED) {
					return;
				}
				if (this.settle_timeout != 0) {
					GLib.Source.remove(this.settle_timeout);
					this.settle_timeout = 0;
				}
				if (this.state != Session.State.BUSY) {
					this.state = Session.State.BUSY;
				}
				this.settle_timeout = GLib.Timeout.add(1500, () => {
					this.settle_timeout = 0;
					if (this.selected || this.state != Session.State.BUSY) {
						return false;
					}
					this.state = Session.State.READY;
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
			if (this.state == Session.State.IDLE) {
				return;
			}
			this.state = Session.State.IDLE;
		}

		/**
		 * Close this tab after ``seconds`` (``0`` = immediately). Callers own the
		 * policy; shared 250ms countdown ticks — subclasses refresh chrome via
		 * {@link close_countdown}.
		 *
		 * @param seconds Delay before {@link close_tab}; ``0`` closes now
		 */
		public void close_in(int seconds)
		{
			// deleted host: never hold EXITED / X-close countdowns
			if (this.connection.deleted && seconds > 0) {
				seconds = 0;
			}
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
			// close_confirmed: delete / Close now already wiped — do not re-arm
			if (this.close_confirmed || this.close_armed || this.close_paused) {
				return;
			}
			this.close_armed = true;
			this.close_left = seconds * 1000;
			this.close_total = seconds * 1000;
			this.close_countdown(this.close_left, this.close_total);
			if (this.close_tick != 0) {
				GLib.Source.remove(this.close_tick);
			}
			this.close_tick = GLib.Timeout.add(250, () => {
				if (this.close_paused) {
					this.close_tick = 0;
					return false;
				}
				this.close_left -= 250;
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
		 * Update close chrome each tick. ``left == 0`` means hide / done.
		 *
		 * @param left Milliseconds remaining
		 * @param total Original delay from {@link close_in} in milliseconds
		 */
		protected virtual void close_countdown(int left, int total)
		{
			this.closing(left, total);
			if (left <= 0 || total <= 0) {
				this.close_bar.visible = false;
				return;
			}
			if (!this.selected) {
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
			var secs = (left + 999) / 1000;
			this.close_progress.text = "Closing in " + secs.to_string() + " seconds…";
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
