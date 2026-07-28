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
	 * One host: {@link Adw.TabView} of {@link Terminal}s with an {@link Adw.TabBar}.
	 * Localhost also keeps path children in the tree as a second switcher.
	 * Open terminals live on {@link Connection.sessions} for the host tree.
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
			this.append(this.tab_bar);
			this.append(this.tab_view);
			this.tab_view.notify["selected-page"].connect(() => {
				this.wire();
				this.changed();
			});
			this.tab_view.close_page.connect((page) => {
				var term = (Terminal) page.child;
				var at = this.terminals.index_of(term);
				this.terminals.remove_at(at);
				this.connection.sessions.remove(at);
				if (at < this.paths.size) {
					var path = this.paths.remove_at(at);
					path.sessions.remove_all();
					this.tree.remove(path);
				}
				this.tab_view.close_page_finish(page, true);
				if (this.tab_view.n_pages > 0) {
					this.wire();
					return true;
				}
				this.current = null;
				this.sync_paths();
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
			this.connection.sessions.append(term);
			term.label_changed.connect(() => {
				var tab = this.tab_view.get_page(term);
				tab.title = term.label();
				this.sync_paths();
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
		}

		/**
		 * Keep Localhost path children in sync with open local shells.
		 */
		public void sync_paths()
		{
			if (this.connection.kind != ConnectionKind.LOCAL) {
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
					child.local_tab = i;
					child.name = term.label();
				} else {
					child = new Connection() {
						uuid = GLib.Uuid.string_random(),
						name = term.label(),
						kind = ConnectionKind.LOCAL_PATH,
						local_tab = i
					};
					this.tree.append(this.connection, child);
					this.paths.add(child);
				}
				if (child.sessions.get_n_items() == 0) {
					child.sessions.append(term);
				} else if (child.sessions.get_item(0) != term) {
					child.sessions.remove_all();
					child.sessions.append(term);
				}
				term.tree_active = i == active;
			}
		}

		/**
		 * Point {@link current} at the selected tab; toggle select marks.
		 */
		private void wire()
		{
			if (this.tab_view.selected_page == null) {
				if (this.current != null) {
					this.current.tree_active = false;
					this.current.select(false);
					this.current = null;
				}
				this.sync_paths();
				return;
			}
			var next = (Terminal) this.tab_view.selected_page.child;
			if (this.current != null && this.current != next) {
				this.current.tree_active = false;
				this.current.select(false);
			}
			this.current = next;
			this.current.tree_active = true;
			this.current.select(this.on_screen);
			this.sync_paths();
		}
	}
}
