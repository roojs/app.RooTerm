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

namespace RooTerm.Terminal
{
	/**
	 * Shared VTE right-click menu for the main window. Owns one
	 * {@link Gtk.PopoverMenu} from a {@link GLib.Menu}; items call ``win.*``
	 * actions (icons + accelerators). Reparents per click; dismisses on
	 * window unmap or target destroy.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.terminal_menu = new Terminal.ContextMenu(this);
	 * this.terminal_menu.popup_for(term, x, y);
	 * }}}
	 */
	public class ContextMenu : GLib.Object
	{
		/**
		 * The real menu widget ({@link Gtk.PopoverMenu} is not subclassable).
		 */
		public Gtk.PopoverMenu menu { get; private set; }
		private weak RooTerm.MainWindow window;
		private weak Base? target;
		private ulong target_destroy_id = 0;

		/**
		 * Build the menu model (parent is set in {@link popup_for}).
		 *
		 * @param window Main window (``win.*`` actions / DBus)
		 */
		public ContextMenu(RooTerm.MainWindow window)
		{
			var edit = new GLib.Menu();
			var copy_item = new GLib.MenuItem("Copy", "win.copy");
			copy_item.set_icon(new GLib.ThemedIcon("edit-copy-symbolic"));
			edit.append_item(copy_item);
			var paste_item = new GLib.MenuItem("Paste", "win.paste");
			paste_item.set_icon(new GLib.ThemedIcon("edit-paste-symbolic"));
			edit.append_item(paste_item);

			var session = new GLib.Menu();
			var fullscreen_item = new GLib.MenuItem("Full screen", "win.fullscreen");
			fullscreen_item.set_icon(new GLib.ThemedIcon("view-fullscreen-symbolic"));
			session.append_item(fullscreen_item);
			var reset_item = new GLib.MenuItem("Reset", "win.reset-terminal");
			reset_item.set_icon(new GLib.ThemedIcon("view-refresh-symbolic"));
			session.append_item(reset_item);
			var close_item = new GLib.MenuItem("Close", "win.close-terminal");
			close_item.set_icon(new GLib.ThemedIcon("window-close-symbolic"));
			session.append_item(close_item);

			var app_section = new GLib.Menu();
			var prefs_item = new GLib.MenuItem("Preferences", "win.preferences");
			prefs_item.set_icon(new GLib.ThemedIcon("preferences-system-symbolic"));
			app_section.append_item(prefs_item);
			var about_item = new GLib.MenuItem("About", "win.about");
			about_item.set_icon(new GLib.ThemedIcon("help-about-symbolic"));
			app_section.append_item(about_item);
			var quit_item = new GLib.MenuItem("Quit", "win.quit");
			quit_item.set_icon(new GLib.ThemedIcon("application-exit-symbolic"));
			app_section.append_item(quit_item);

			var model = new GLib.Menu();
			model.append_section(null, edit);
			model.append_section(null, session);
			model.append_section(null, app_section);

			this.window = window;
			this.menu = new Gtk.PopoverMenu.from_model(model) {
				has_arrow = false
			};
			this.window.unmap.connect(() => {
				this.popdown();
			});
		}

		/**
		 * Dismiss the popover (window hide / Toggle / tab gone).
		 */
		public void popdown()
		{
			this.menu.popdown();
		}

		/**
		 * Point at ``term``, reparent to its VTE, and popup at the click.
		 *
		 * @param term Tab that was right-clicked
		 * @param x Click X in the VTE
		 * @param y Click Y in the VTE
		 */
		public void popup_for(Base term, double x, double y)
		{
			if (this.target_destroy_id != 0 && this.target != null) {
				this.target.disconnect(this.target_destroy_id);
				this.target_destroy_id = 0;
			}
			this.target = term;
			this.target_destroy_id = term.destroy.connect(() => {
				this.popdown();
				this.target_destroy_id = 0;
				this.target = null;
			});
			if (this.menu.get_parent() != term.terminal) {
				if (this.menu.get_parent() != null) {
					this.menu.unparent();
				}
				this.menu.set_parent(term.terminal);
			}
			/* Never disable win.copy here — it backs Ctrl+Shift+C; a sticky
			 * disable lets the chord fall through to VTE as ^C. */
			this.menu.pointing_to = Gdk.Rectangle() {
				x = (int) x,
				y = (int) y,
				width = 1,
				height = 1
			};
			this.menu.popup();
		}
	}
}
