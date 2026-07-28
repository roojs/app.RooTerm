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
	 * One host: {@link Adw.TabView} of {@link Terminal}s.
	 * SSH hosts show an {@link Adw.TabBar}; Localhost has no tab bar — path tree selects the shell.
	 * Owns selection → session marks; keyed in the stack by {@link Connection.uuid}.
	 */
	public class HostPage : Gtk.Box
	{
		public Connection connection;
		public HostTreeNodes tree;
		public Adw.TabView tab_view;
		public Adw.TabBar tab_bar;
		/**
		 * Selected terminal on this page (null when no tabs).
		 */
		public Terminal current;
		/**
		 * Terminals on this page, parallel to tab / path order.
		 */
		public Gee.ArrayList<Terminal> terminals = new Gee.ArrayList<Terminal>();
		/**
		 * Localhost path rows, parallel to {@link terminals} (looked up by index).
		 */
		private Gee.ArrayList<Connection> paths = new Gee.ArrayList<Connection>();
		private bool on_screen = false;

		/**
		 * Emitted when the last terminal is closed.
		 */
		public signal void empty();

		/**
		 * Emitted when the selected terminal or its label should refresh the window title.
		 */
		public signal void changed();

		/**
		 * Build an empty host page for ``connection``.
		 *
		 * @param connection Host this page belongs to
		 * @param tree Root host tree (gateway for Localhost path children)
		 */
		public HostPage(Connection connection, HostTreeNodes tree)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				hexpand: true,
				vexpand: true
			);
			this.connection = connection;
			this.tree = tree;
			this.tab_view = new Adw.TabView() {
				hexpand = true,
				vexpand = true
			};
			this.tab_bar = new Adw.TabBar() {
				view = this.tab_view
			};
			if (!connection.is_local) {
				this.append(this.tab_bar);
			}
			this.append(this.tab_view);
			this.tab_view.notify["selected-page"].connect(() => {
				this.wire();
				this.changed();
			});
			this.tab_view.close_page.connect((page) => {
				var term = (Terminal) page.child;
				var at = this.terminals.index_of(term);
				this.terminals.remove_at(at);
				if (at < this.paths.size) {
					this.tree.remove(this.paths.remove_at(at));
				}
				this.tab_view.close_page_finish(page, true);
				if (this.tab_view.n_pages > 0) {
					this.wire();
					return true;
				}
				this.current = null;
				this.connection.active_tab = -1;
				this.sync();
				this.empty();
				return true;
			});
		}

		/**
		 * Add ``term`` as a new tab and return its {@link Adw.TabPage}.
		 *
		 * @param term Terminal to show
		 * @return Tab page for title / close wiring
		 */
		public Adw.TabPage add(Terminal term)
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
		 * For Localhost, also sync ephemeral path children under the root row.
		 */
		public void sync()
		{
			if (!this.connection.is_local) {
				var titles = new Gee.ArrayList<string>();
				var states = new Gee.ArrayList<SessionState>();
				foreach (var term in this.terminals) {
					titles.add(term.label());
					states.add(term.state);
				}
				this.connection.open_count = this.terminals.size;
				this.connection.tab_titles = titles;
				this.connection.tab_states = states;
				return;
			}
			var active = -1;
			if (this.tab_view.selected_page != null) {
				active = this.tab_view.get_page_position(this.tab_view.selected_page);
			}
			for (var i = 0; i < this.terminals.size; i++) {
				var term = this.terminals.get(i);
				Connection child;
				if (i < this.paths.size) {
					child = this.paths.get(i);
					child.name = term.label();
					child.local_tab = i;
				} else {
					child = new Connection() {
						uuid = GLib.Uuid.string_random(),
						name = term.label(),
						local_path = true,
						local_tab = i
					};
					this.tree.append(this.connection, child);
					this.paths.add(child);
				}
				var titles = new Gee.ArrayList<string>();
				titles.add(term.label());
				var states = new Gee.ArrayList<SessionState>();
				states.add(term.state);
				child.tab_titles = titles;
				child.tab_states = states;
				child.open_count = 1;
				child.active_tab = i == active ? 0 : -1;
			}
			this.connection.open_count = 0;
			this.connection.active_tab = active;
			this.connection.tab_titles = new Gee.ArrayList<string>();
			this.connection.tab_states = new Gee.ArrayList<SessionState>();
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
				this.sync();
				return;
			}
			var next = (Terminal) this.tab_view.selected_page.child;
			if (this.current != null && this.current != next) {
				this.current.select(false);
			}
			this.current = next;
			this.connection.active_tab = this.tab_view.get_page_position(this.tab_view.selected_page);
			if (this.current != null) {
				this.current.select(this.on_screen);
			}
			this.sync();
		}
	}
}
