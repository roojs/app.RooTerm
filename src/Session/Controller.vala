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

namespace RooTerm.Session
{
	/**
	 * Opens / closes / focuses host terminal pages; owns the display string
	 * for window title and search placeholder.
	 */
	public class Controller : GLib.Object
	{
		public Host.Stack stack;
		public Host.TreeNodes tree;
		public RooTerm.Config config;
		/**
		 * Localhost connection (same instance as {@link MainWindow.localhost}).
		 */
		public Host.Connection localhost;
		public string display = "Roo Term";
		/**
		 * Open host pages by connection uuid (same key as {@link Gtk.Stack} names).
		 */
		private Gee.HashMap<string, Host.Page> by_uuid = new Gee.HashMap<string, Host.Page>();
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
		public signal void sudo_password_failed(Host.Connection connection);

		/**
		 * @param stack Outer host stack to manage
		 * @param tree Root host tree (gateway; Localhost path children)
		 * @param config App config (passed into new terminals for opacity)
		 * @param localhost Localhost connection for empty-stack fallback
		 */
		public Controller(Host.Stack stack, Host.TreeNodes tree, RooTerm.Config config,
			Host.Connection localhost)
		{
			this.stack = stack;
			this.tree = tree;
			this.config = config;
			this.localhost = localhost;
			this.stack.pages.notify["visible-child"].connect(() => {
				var next = this.stack.pages.visible_child as Host.Page;
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
		 * {@link Host.ConnectionKind.LXC} tabs share the parent host page, like
		 * {@link Host.ConnectionKind.LOCAL_PATH} on Localhost.
		 *
		 * Caller sets stream flags if needed, then {@link Terminal.Ssh.spawn} and
		 * ``terminal.grab_focus()`` when ready.
		 *
		 * @param connection Host to open
		 * @param stream Optional stream to adopt (``install_key`` / signals)
		 * @return The new terminal tab contents (not yet spawned)
		 */
		public Terminal.Ssh create(Host.Connection connection, Terminal.Stream? stream = null)
		{
			var page_connection = connection.kind == Host.ConnectionKind.LXC
				? connection.parent : connection;
			var page = this.by_uuid.get(page_connection.uuid);
			if (page == null) {
				page = new Host.Page(page_connection, this.tree, this.config);
				page.empty.connect(() => {
					this.close(page);
				});
				page.changed.connect(() => {
					this.focus();
				});
				this.by_uuid.set(page_connection.uuid, page);
				this.stack.pages.add_named(page, page_connection.uuid);
				var win = this.stack.get_root() as MainWindow;
				if (win != null && win.fullscreen) {
					this.stack.fullscreen(true);
				}
			}

			var term = new Terminal.Ssh(connection, this.config, stream);
			var tab = page.add(term);
			term.close_tab.connect(() => {
				page.tab_view.close_page(tab);
			});
			page.tab_view.selected_page = tab;
			this.stack.pages.visible_child = page;
			this.focus();
			return term;
		}

		/**
		 * Open a local shell tab under Localhost (creates host page if needed).
		 * Pass Localhost for a new tab, or an existing {@link Host.ConnectionKind.LOCAL_PATH}
		 * to reopen that row without inventing another.
		 *
		 * @param connection Localhost, or a Localhost path child to restore
		 * @param cwd Working directory (home when empty; path row uses {@link Host.Connection.cwd})
		 * @return The new local terminal
		 */
		public Terminal.Local open_local(Host.Connection connection, string cwd = "")
		{
			if (connection.kind == Host.ConnectionKind.LOCAL_PATH && cwd.length == 0) {
				cwd = connection.cwd;
			}
			// Host.Page is always the Localhost row (parent when restoring a path).
			var page_connection = connection.kind == Host.ConnectionKind.LOCAL_PATH
				? connection.parent : connection;
			var page = this.by_uuid.get(page_connection.uuid);
			if (page == null) {
				page = new Host.Page(page_connection, this.tree, this.config);
				page.empty.connect(() => {
					this.close(page);
				});
				page.changed.connect(() => {
					this.focus();
				});
				this.by_uuid.set(page_connection.uuid, page);
				this.stack.pages.add_named(page, page_connection.uuid);
				var win = this.stack.get_root() as MainWindow;
				if (win != null && win.fullscreen) {
					this.stack.fullscreen(true);
				}
			}

			var term = new Terminal.Local(connection, this.config, cwd);
			var tab = page.add(term);
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
		 * When no terminals remain, opens a fresh local shell so the window is never blank.
		 *
		 * @param page Host.Page to remove
		 */
		public void close(Host.Page page)
		{
			page.connection.sessions.remove_all();
			this.by_uuid.unset(page.connection.uuid);
			if (this.shown_uuid == page.connection.uuid) {
				this.shown_uuid = "";
			}
			this.stack.pages.remove(page);
			var visible = this.stack.pages.visible_child as Host.Page;
			if (visible != null && visible.current != null) {
				this.focus();
				return;
			}
			var other = this.stack.pages.get_first_child() as Host.Page;
			if (other != null) {
				this.stack.pages.visible_child = other;
				this.focus();
				return;
			}
			GLib.Idle.add(() => {
				this.open_local(this.localhost);
				return false;
			});
			this.focus();
		}

		/**
		 * Close the focused terminal tab (window-close hook). Shows another
		 * open terminal when possible. Closing the last confirmed tab returns
		 * false so a docked window can hide (a replacement local opens idle).
		 *
		 * @return true if a tab was closed and the window should stay up
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
			var term = (Terminal.Base) page.tab_view.selected_page.child;
			var was_last = page.tab_view.n_pages == 1 && this.by_uuid.size == 1
				&& term.close_confirmed;
			page.tab_view.close_page(page.tab_view.selected_page);
			this.focus();
			return !was_last;
		}

		/**
		 * Move selection by ``delta`` tabs within the visible host page.
		 *
		 * @param delta ``-1`` previous / ``1`` next (wraps)
		 */
		public void select_tab(int delta)
		{
			if (this.shown_uuid.length == 0 || !this.by_uuid.has_key(this.shown_uuid)) {
				return;
			}
			var page = this.by_uuid.get(this.shown_uuid);
			if (page.tab_view.n_pages < 2 || page.tab_view.selected_page == null) {
				return;
			}
			var next = (page.tab_view.get_page_position(page.tab_view.selected_page) + delta)
				% page.tab_view.n_pages;
			next = next < 0 ? next + page.tab_view.n_pages : next;
			page.tab_view.selected_page = page.tab_view.get_nth_page(next);
			this.focus();
			if (page.current != null) {
				page.current.terminal.grab_focus();
			}
		}

		/**
		 * Select all text in the focused VTE.
		 */
		public void select_all()
		{
			if (this.shown_uuid.length == 0 || !this.by_uuid.has_key(this.shown_uuid)) {
				return;
			}
			var page = this.by_uuid.get(this.shown_uuid);
			if (page.current == null) {
				return;
			}
			page.current.terminal.select_all();
		}

		/**
		 * Refresh {@link display} from the current terminal and put the
		 * keyboard in that VTE (or ``Roo Term`` when none).
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
			page.current.terminal.grab_focus();
		}
	}
}
