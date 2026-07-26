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
		 * Fired when {@link display} changes.
		 */
		public signal void display_changed();

		/**
		 * @param stack Outer host stack to manage
		 */
		public SessionController(HostStack stack)
		{
			this.stack = stack;
		}

		/**
		 * Open a new SSH terminal tab for ``connection`` (creates host page if needed).
		 *
		 * @param connection Host to open
		 */
		public void open(Connection connection)
		{
			var page = this.stack.pages.get_child_by_name(connection.uuid) as HostPage;
			if (page == null) {
				page = new HostPage(connection);
				page.empty.connect(() => {
					this.close(page);
				});
				page.tab_view.notify["selected-page"].connect(() => {
					page.connection.open_count = page.tab_view.n_pages;
					page.connection.active_tab = -1;
					if (page.tab_view.selected_page == null) {
						this.focus();
						return;
					}
					for (var i = 0; i < page.tab_view.n_pages; i++) {
						if (page.tab_view.get_nth_page(i) != page.tab_view.selected_page) {
							continue;
						}
						page.connection.active_tab = i;
						break;
					}
					this.focus();
				});
				this.stack.pages.add_named(page, connection.uuid);
			}

			var term = new SshTerminal(connection, this.terminal_font);
			var tab = page.tab_view.append(term);
			tab.title = term.label();
			term.exited.connect(() => {
				GLib.Timeout.add_seconds(10, () => {
					for (var i = 0; i < page.tab_view.n_pages; i++) {
						if (page.tab_view.get_nth_page(i) != tab) {
							continue;
						}
						page.tab_view.close_page(tab);
						break;
					}
					return false;
				});
			});
			term.label_changed.connect(() => {
				tab.title = term.label();
				this.focus();
			});
			term.spawn();
			page.tab_view.selected_page = tab;
			connection.open_count = page.tab_view.n_pages;
			connection.active_tab = page.tab_view.n_pages - 1;
			this.stack.pages.visible_child = page;
			this.focus();
			term.terminal.grab_focus();
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
			this.stack.pages.remove(page);
			var visible = this.stack.pages.visible_child as HostPage;
			if (visible != null && visible.tab_view.n_pages > 0) {
				this.focus();
				return;
			}
			for (var child = this.stack.pages.get_first_child();
					 child != null; child = child.get_next_sibling()) {
				var other = child as HostPage;
				if (other == null || other.tab_view.n_pages == 0) {
					continue;
				}
				this.stack.pages.visible_child = other;
				this.focus();
				return;
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
			var page = this.stack.pages.visible_child as HostPage;
			if (page == null || page.tab_view.n_pages == 0) {
				return false;
			}
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
			var page = this.stack.pages.visible_child as HostPage;
			if (page == null || page.tab_view.n_pages == 0) {
				this.display = "Roo Term";
				this.display_changed();
				return;
			}
			if (page.tab_view.selected_page == null) {
				this.display = "Roo Term";
				this.display_changed();
				return;
			}
			var term = page.tab_view.selected_page.child as SshTerminal;
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
