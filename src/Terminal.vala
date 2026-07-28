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
		 * Mark for the host-tree session icon (active look is focus, not this).
		 */
		public SessionState state = SessionState.IDLE;
		protected bool selected = true;
		protected uint settle_timeout = 0;

		/**
		 * Emitted when the tab should be closed (exit / countdown).
		 */
		public signal void close_tab();

		/**
		 * Emitted when {@link label} should refresh.
		 */
		public signal void label_changed();

		/**
		 * Emitted when {@link state} changes (busy / ready / idle / dead).
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
				var path = GLib.File.new_for_uri(uri.to_string()).get_path();
				if (path == null) {
					return;
				}
				this.cwd = path;
				this.label_changed();
			});
			this.terminal.contents_changed.connect(() => {
				if (this.selected || this.state == SessionState.DEAD) {
					return;
				}
				if (this.settle_timeout != 0) {
					GLib.Source.remove(this.settle_timeout);
					this.settle_timeout = 0;
				}
				if (this.state != SessionState.BUSY) {
					this.state = SessionState.BUSY;
					this.state_changed();
				}
				this.settle_timeout = GLib.Timeout.add(1500, () => {
					this.settle_timeout = 0;
					if (this.selected || this.state != SessionState.BUSY) {
						return false;
					}
					this.state = SessionState.READY;
					this.state_changed();
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
			this.state_changed();
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
