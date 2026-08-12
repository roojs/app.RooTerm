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
	 * Outer stack of {@link Page}s keyed by connection uuid.
	 */
	public class Stack : Gtk.Box
	{
		public Gtk.Stack pages;

		/**
		 * Empty stack; pages are added by {@link Session.Controller}.
		 */
		public Stack()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
			this.add_css_class("vte-path");
			this.pages = new Gtk.Stack() {
				hexpand = true,
				vexpand = true
			};
			this.pages.add_css_class("vte-path");
			this.append(this.pages);
		}

		/**
		 * Full-screen chrome + docked geometry.
		 *
		 * With ``window`` docked: ``redock``, then after the Shell ease
		 * (~320 ms) flip chrome and ``set_default_size``. Without ``window``
		 * (or undocked): chrome only — used when adding pages while already
		 * full screen.
		 *
		 * Not ideal: walks every host page, including ones that are not
		 * visible — only the current page needs the chrome flip. Leave as-is
		 * for now.
		 *
		 * @param on True = strip on top (full-screen chrome); false = bottom
		 * @param window Main window when the action owns redock / size
		 */
		public void fullscreen(bool on, MainWindow? window = null)
		{
			if (window != null && window.is_docked) {
				window.dbus.redock(on);
				GLib.Timeout.add(320, () => {
					this.fullscreen(window.fullscreen);
					window.set_default_size(
						window.fullscreen
							? window.monitor_geo.width
							: window.monitor_geo.width * window.config.width / 100,
						window.fullscreen
							? window.monitor_geo.height
							: window.monitor_geo.height * window.config.height / 100
					);
					return false;
				});
				return;
			}
			for (var child = this.pages.get_first_child();
					child != null; child = child.get_next_sibling()) {
				var page = child as Page;
				if (page == null) {
					continue;
				}
				page.tab_bar.unparent();
				if (on) {
					page.chrome_top.append(page.tab_bar);
				} else {
					page.chrome_bottom.append(page.tab_bar);
				}
				page.tab_bar.fs_btn.icon_name = on
					? "view-restore-symbolic" : "view-fullscreen-symbolic";
				page.tab_bar.fs_btn.tooltip_text = on
					? "Exit full screen" : "Full screen";
			}
		}
	}
}
