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

namespace RooTerm.Host
{
	/**
	 * One host: {@link Adw.TabView} of {@link Terminal.Base}s with an {@link Adw.TabBar}
	 * at the bottom (always shown). Localhost children are {@link ConnectionKind.LOCAL_PATH}
	 * rows owned by each local tab’s {@link Terminal.Base.connection}.
	 * Tab-strip ``+`` runs ``win.new-terminal`` (same as Ctrl+Shift+T).
	 * Open terminals live on {@link Connection.sessions} for the host tree.
	 */
	public class Page : Gtk.Box
	{
		public Connection connection;
		public TreeNodes tree;
		public Adw.TabView tab_view;
		public Adw.TabBar tab_bar;
		/**
		 * Selected terminal on this page (null when no tabs).
		 */
		public Terminal.Base current;
		/**
		 * Terminals on this page, parallel to tab order.
		 */
		public Gee.ArrayList<Terminal.Base> terminals = new Gee.ArrayList<Terminal.Base>();
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
		public Page(Connection connection, TreeNodes tree)
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
			this.tab_view.add_css_class("vte-host");
			this.tab_bar = new Adw.TabBar() {
				view = this.tab_view,
				autohide = false,
				expand_tabs = false,
				hexpand = true,
				end_action_widget = new Gtk.Button.from_icon_name("list-add-symbolic") {
					tooltip_text = "Ctrl+Shift+T",
					has_frame = false,
					action_name = "win.new-terminal"
				}
			};
			this.tab_bar.add_css_class("thin-tabbar");
			this.append(this.tab_view);
			this.append(this.tab_bar);
			this.tab_view.notify["selected-page"].connect(() => {
				this.wire();
				this.changed();
			});
			this.tab_view.close_page.connect((page) => {
				var term = (Terminal.Base) page.child;
				if (!term.close_confirmed) {
					term.close_in(5);
					this.tab_view.close_page_finish(page, false);
					return true;
				}
				var at = this.terminals.index_of(term);
				this.terminals.remove_at(at);
				this.connection.sessions.remove(at);
				if (term.connection.kind == ConnectionKind.LOCAL_PATH) {
					term.connection.sessions.remove_all();
					this.tree.remove(term.connection);
				}
				this.tab_view.close_page_finish(page, true);
				if (this.tab_view.n_pages > 0) {
					this.wire();
					return true;
				}
				this.current = null;
				this.empty();
				return true;
			});
		}

		/**
		 * Add ``term`` as a new tab and return its {@link Adw.TabPage}.
		 *
		 * @param term Terminal.Base to show
		 * @return Tab page for title / close wiring
		 */
		public Adw.TabPage add(Terminal.Base term)
		{
			this.terminals.add(term);
			this.connection.sessions.append(term);
			term.label_changed.connect(() => {
				var tab = this.tab_view.get_page(term);
				var text = term.label();
				tab.tooltip = text;
				tab.title = text;
				if (term.connection.kind == ConnectionKind.LOCAL_PATH && term.connection.name != text) {
					term.connection.name = text;
				}
				this.changed();
			});
			var tab = this.tab_view.append(term);
			var text = term.label();
			tab.tooltip = text;
			tab.title = text;
			if (this.connection.kind == ConnectionKind.LOCAL) {
				var row = new Connection() {
					uuid = GLib.Uuid.string_random(),
					name = term.label(),
					kind = ConnectionKind.LOCAL_PATH
				};
				term.connection = row;
				row.sessions.append(term);
				this.tree.append(this.connection, row);
			}
			return tab;
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
				return;
			}
			var next = (Terminal.Base) this.tab_view.selected_page.child;
			if (this.current != null && this.current != next) {
				this.current.tree_active = false;
				this.current.select(false);
			}
			this.current = next;
			this.current.tree_active = true;
			this.current.select(this.on_screen);
		}
	}
}
