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
		 * @param stack Outer host stack to manage
		 */
		public SessionController(HostStack stack)
		{
			this.stack = stack;
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
		 * Open a new SSH terminal tab for ``connection`` (creates host page if needed).
		 *
		 * @param connection Host to open
		 * @param stream Optional preconfigured {@link SshStream} (``install_key`` / ``list_containers`` / signals)
		 * @return The new terminal tab contents
		 */
		public SshTerminal open(Connection connection, SshStream? stream = null)
		{
			HostPage page;
			if (this.by_uuid.has_key(connection.uuid)) {
				page = this.by_uuid.get(connection.uuid);
			} else {
				page = new HostPage(connection);
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
			page.connection.open_count = 0;
			page.connection.active_tab = -1;
			page.connection.tab_titles = new Gee.ArrayList<string>();
			page.connection.tab_states = new Gee.ArrayList<SessionState>();
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
			var term = this.by_uuid.get(this.shown_uuid).current;
			if (term == null) {
				this.display = "Roo Term";
				this.display_changed();
				return;
			}
			this.display = term.label();
			this.display_changed();
		}
	}
}
