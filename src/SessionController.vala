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
	 * Opens / closes / focuses host terminal pages; owns the display string
	 * for window title and search placeholder.
	 */
	public class SessionController : GLib.Object
	{
		public HostStack stack;
		public HostTreeNodes tree;
		public string display = "Roo Term";
		/**
		 * VTE font from Ásbrú defaults (``Monospace 9`` etc.).
		 */
		public string terminal_font = "Monospace 9";
		/**
		 * Open host pages by connection uuid (same key as {@link Gtk.Stack} names).
		 */
		private Gee.HashMap<string, HostPage> by_uuid = new Gee.HashMap<string, HostPage>();
		/**
		 * Uuid of the currently visible host page (empty when none).
		 */
		private string shown_uuid = "";

		/**
		 * Fired when {@link display} changes.
		 */
		public signal void display_changed();

		/**
		 * Fired when ``sudo -i`` rejects the connection password.
		 *
		 * @param connection Host whose sudo password failed
		 */
		public signal void sudo_password_failed(Connection connection);

		/**
		 * @param stack Outer host stack to manage
		 * @param tree Root host tree (gateway; Localhost path children)
		 */
		public SessionController(HostStack stack, HostTreeNodes tree)
		{
			this.stack = stack;
			this.tree = tree;
			this.stack.pages.notify["visible-child"].connect(() => {
				var next = this.stack.pages.visible_child as HostPage;
				var next_uuid = next != null ? next.connection.uuid : "";
				if (this.shown_uuid.length > 0 && this.shown_uuid != next_uuid
						&& this.by_uuid.has_key(this.shown_uuid)) {
					this.by_uuid.get(this.shown_uuid).view(false);
				}
				if (next != null) {
					next.view(true);
				}
				this.shown_uuid = next_uuid;
				this.focus();
			});
		}

		/**
		 * Create an SSH terminal tab for ``connection`` without spawning (host page if needed).
		 *
		 * Caller sets stream flags if needed, then {@link SshTerminal.spawn} and
		 * ``terminal.grab_focus()`` when ready.
		 *
		 * @param connection Host to open
		 * @param stream Optional stream to adopt (``install_key`` / signals)
		 * @return The new terminal tab contents (not yet spawned)
		 */
		public SshTerminal create(Connection connection, SshStream? stream = null)
		{
			HostPage page;
			if (this.by_uuid.has_key(connection.uuid)) {
				page = this.by_uuid.get(connection.uuid);
			} else {
				page = new HostPage(connection, this.tree);
				page.empty.connect(() => {
					this.close(page);
				});
				page.changed.connect(() => {
					this.focus();
				});
				this.by_uuid.set(connection.uuid, page);
				this.stack.pages.add_named(page, connection.uuid);
			}

			var term = new SshTerminal(connection, this.terminal_font, stream);
			var tab = page.add(term);
			tab.title = term.label();
			term.close_tab.connect(() => {
				page.tab_view.close_page(tab);
			});
			page.tab_view.selected_page = tab;
			this.stack.pages.visible_child = page;
			this.focus();
			return term;
		}

		/**
		 * Open another tab like the focused one: SSH clone via {@link OpenSession},
		 * or local shell in the same cwd. Falls back to a new local shell in home
		 * when nothing is focused.
		 *
		 * @param localhost Localhost connection for local / empty fallback
		 * @param window Main window (for {@link OpenSession})
		 */
		public void open_new(Connection localhost, MainWindow window)
		{
			if (this.shown_uuid.length == 0 || !this.by_uuid.has_key(this.shown_uuid)) {
				this.open_local(localhost);
				return;
			}
			var page = this.by_uuid.get(this.shown_uuid);
			var term = page.current;
			if (term == null) {
				this.open_local(localhost);
				return;
			}
			if (term is SshTerminal) {
				var job = new OpenSession(window, term.connection);
				GLib.Idle.add(() => {
					window.present();
					job.terminal.terminal.grab_focus();
					return false;
				});
				job.run.begin((obj, res) => {
					try {
						job.run.end(res);
					} catch (JobError e) {
						GLib.warning("open session failed name=%s: %s",
							term.connection.name, e.message);
					}
				});
				return;
			}
			var local = term as LocalTerminal;
			if (local != null) {
				var dir = local.cwd.length > 0 ? local.cwd : local.start_cwd;
				this.open_local(localhost, dir);
				return;
			}
			this.open_local(localhost);
		}

		/**
		 * Open a local shell tab under Localhost (creates host page if needed).
		 *
		 * @param connection Localhost connection
		 * @param cwd Working directory (home when empty)
		 * @return The new local terminal
		 */
		public LocalTerminal open_local(Connection connection, string cwd = "")
		{
			HostPage page;
			if (this.by_uuid.has_key(connection.uuid)) {
				page = this.by_uuid.get(connection.uuid);
			} else {
				page = new HostPage(connection, this.tree);
				page.empty.connect(() => {
					this.close(page);
				});
				page.changed.connect(() => {
					this.focus();
				});
				this.by_uuid.set(connection.uuid, page);
				this.stack.pages.add_named(page, connection.uuid);
			}

			var term = new LocalTerminal(connection, this.terminal_font, cwd);
			var tab = page.add(term);
			tab.title = term.label();
			term.close_tab.connect(() => {
				page.tab_view.close_page(tab);
			});
			term.spawn();
			page.tab_view.selected_page = tab;
			this.stack.pages.visible_child = page;
			this.focus();
			term.terminal.grab_focus();
			return term;
		}

		/**
		 * Remove an empty host page from the stack; show another open host if any.
		 *
		 * @param page Page to remove
		 */
		public void close(HostPage page)
		{
			page.connection.sessions.remove_all();
			this.by_uuid.unset(page.connection.uuid);
			if (this.shown_uuid == page.connection.uuid) {
				this.shown_uuid = "";
			}
			this.stack.pages.remove(page);
			var visible = this.stack.pages.visible_child as HostPage;
			if (visible != null && visible.current != null) {
				this.focus();
				return;
			}
			var other = this.stack.pages.get_first_child() as HostPage;
			if (other != null) {
				this.stack.pages.visible_child = other;
			}
			this.focus();
		}

		/**
		 * Close the focused terminal tab (window-close hook). Shows another
		 * open terminal when possible.
		 *
		 * @return true if a tab was closed (inhibit window destroy)
		 */
		public bool close_current()
		{
			if (this.shown_uuid.length == 0 || !this.by_uuid.has_key(this.shown_uuid)) {
				return false;
			}
			var page = this.by_uuid.get(this.shown_uuid);
			if (page.tab_view.selected_page == null) {
				return false;
			}
			page.tab_view.close_page(page.tab_view.selected_page);
			this.focus();
			return true;
		}

		/**
		 * Refresh {@link display} from the focused terminal (or ``Roo Term``).
		 */
		public void focus()
		{
			if (this.shown_uuid.length == 0 || !this.by_uuid.has_key(this.shown_uuid)) {
				this.display = "Roo Term";
				this.display_changed();
				return;
			}
			var page = this.by_uuid.get(this.shown_uuid);
			if (page.current == null) {
				this.display = "Roo Term";
				this.display_changed();
				return;
			}
			this.display = page.current.label();
			this.display_changed();
		}
	}
}
