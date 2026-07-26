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
	 * One host: tab bar + {@link Adw.TabView} of {@link SshTerminal}s.
	 */
	public class HostPage : Gtk.Box
	{
		public Connection connection;
		public Adw.TabView tab_view;
		public Adw.TabBar tab_bar;

		/**
		 * Emitted when the last terminal tab is closed.
		 */
		public signal void empty();

		/**
		 * Build an empty host page for ``connection``.
		 *
		 * @param connection Host this page belongs to
		 */
		public HostPage(Connection connection)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL, 
				spacing: 0, 
				hexpand: true, 
				vexpand: true
			);
			this.connection = connection;
			this.tab_view = new Adw.TabView() {
				hexpand = true,
				vexpand = true
			};
			this.tab_bar = new Adw.TabBar() {
				view = this.tab_view
			};
			this.append(this.tab_bar);
			this.append(this.tab_view);
			this.tab_view.close_page.connect((page) => {
				this.tab_view.close_page_finish(page, true);
				this.connection.open_count = this.tab_view.n_pages;
				this.connection.active_tab = -1;
				if (this.tab_view.n_pages == 0) {
					this.empty();
					return true;
				}
				if (this.tab_view.selected_page == null) {
					return true;
				}
				for (var i = 0; i < this.tab_view.n_pages; i++) {
					if (this.tab_view.get_nth_page(i) != this.tab_view.selected_page) {
						continue;
					}
					this.connection.active_tab = i;
					break;
				}
				return true;
			});
		}
	}
}
