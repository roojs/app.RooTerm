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
	 * Owns tab selection → session marks; keyed in the stack by {@link Connection.uuid}.
	 */
	public class HostPage : Gtk.Box
	{
		public Connection connection;
		public Adw.TabView tab_view;
		public Adw.TabBar tab_bar;
		/**
		 * Selected terminal on this page (null when no tabs).
		 */
		public SshTerminal current;
		/**
		 * Terminals on this page, parallel to tab order.
		 */
		public Gee.ArrayList<SshTerminal> terminals = new Gee.ArrayList<SshTerminal>();
		private bool on_screen = false;

		/**
		 * Emitted when the last terminal tab is closed.
		 */
		public signal void empty();

		/**
		 * Emitted when the selected tab or its label should refresh the window title.
		 */
		public signal void changed();

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
			this.tab_view.notify["selected-page"].connect(() => {
				this.wire();
				this.changed();
			});
			this.tab_view.close_page.connect((page) => {
				var term = page.child as SshTerminal;
				if (term != null) {
					this.terminals.remove(term);
				}
				this.tab_view.close_page_finish(page, true);
				this.connection.open_count = this.tab_view.n_pages;
				if (this.tab_view.n_pages == 0) {
					this.current = null;
					this.connection.active_tab = -1;
					this.connection.tab_titles = new Gee.ArrayList<string>();
					this.connection.tab_states = new Gee.ArrayList<SessionState>();
					this.empty();
					return true;
				}
				this.wire();
				return true;
			});
		}

		/**
		 * Add ``term`` as a new tab and return its {@link Adw.TabPage}.
		 *
		 * @param term Terminal to show
		 * @return Tab page for title / close wiring
		 */
		public Adw.TabPage add(SshTerminal term)
		{
			this.terminals.add(term);
			term.state_changed.connect(() => {
				this.sync();
			});
			term.label_changed.connect(() => {
				var tab = this.tab_view.get_page(term);
				tab.title = term.label();
				this.sync();
				this.changed();
			});
			return this.tab_view.append(term);
		}

		/**
		 * This page is (or is not) the stack's visible child; updates mark select.
		 *
		 * @param on true when this host page is shown
		 */
		public void view(bool on)
		{
			if (this.on_screen == on) {
				return;
			}
			this.on_screen = on;
			if (this.current != null) {
				this.current.select(on);
			}
			this.sync();
		}

		/**
		 * Push tab titles / states onto {@link connection} for the host tree.
		 */
		public void sync()
		{
			var titles = new Gee.ArrayList<string>();
			var states = new Gee.ArrayList<SessionState>();
			foreach (var term in this.terminals) {
				titles.add(term.label());
				states.add(term.state);
			}
			this.connection.open_count = this.terminals.size;
			this.connection.tab_titles = titles;
			this.connection.tab_states = states;
		}

		/**
		 * Point {@link current} at the selected tab; toggle select marks.
		 */
		private void wire()
		{
			if (this.tab_view.selected_page == null) {
				if (this.current != null) {
					this.current.select(false);
					this.current = null;
				}
				this.connection.active_tab = -1;
				this.connection.open_count = this.tab_view.n_pages;
				this.sync();
				return;
			}
			var next = this.tab_view.selected_page.child as SshTerminal;
			if (this.current != null && this.current != next) {
				this.current.select(false);
			}
			this.current = next;
			this.connection.active_tab = this.tab_view.get_page_position(this.tab_view.selected_page);
			this.connection.open_count = this.tab_view.n_pages;
			if (this.current != null) {
				this.current.select(this.on_screen);
			}
			this.sync();
		}
	}
}
