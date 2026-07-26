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
	 * Main window: header (Roo Term + search placeholder) and a sanity VTE shell.
	 */
	public class MainWindow : Adw.ApplicationWindow
	{
		private Adw.HeaderBar header_bar;
		private Gtk.Entry search_entry;
		private Gtk.Stack host_stack;
		private Vte.Terminal terminal;

		/**
		 * Builds the phase-1 shell: title, search stub, and one local VTE page.
		 *
		 * @param app Owning {@link Application}
		 */
		public MainWindow(Application app)
		{
			Object(
				application: app,
				title: "Roo Term",
				default_width: 1100,
				default_height: 700
			);

		this.header_bar = new Adw.HeaderBar();
			var title_label = new Gtk.Label("Roo Term");
			title_label.add_css_class("heading");
			this.header_bar.pack_start(title_label);

			this.search_entry = new Gtk.Entry() {
				placeholder_text = "Ctrl+Shift+O",
				hexpand = true,
				width_request = 320
			};
			this.header_bar.set_title_widget(this.search_entry);

			this.host_stack = new Gtk.Stack();
			this.terminal = new Vte.Terminal() {
				hexpand = true,
				vexpand = true
			};
			this.terminal.set_size(80, 24);

			var scrolled = new Gtk.ScrolledWindow() {
				child = this.terminal,
				hexpand = true,
				vexpand = true
			};
			this.host_stack.add_named(scrolled, "local");
			this.host_stack.set_visible_child_name("local");

			var shell = GLib.Environment.get_variable("SHELL");
			if (shell == null || shell.length == 0) {
				shell = "/bin/bash";
			}

			this.terminal.spawn_async(
				Vte.PtyFlags.DEFAULT,
				null,
				{ shell },
				null,
				GLib.SpawnFlags.SEARCH_PATH,
				null,
				-1,
				null,
				(term, pid, error) => {
					if (error != null) {
						GLib.warning("local shell spawn failed: %s", error.message);
						return;
					}
					GLib.debug("local shell pid=%d", pid);
				}
			);

			var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			content.append(this.header_bar);
			content.append(this.host_stack);
			this.content = content;
		}
	}
}
