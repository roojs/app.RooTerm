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
	 * Context menu for {@link HostTree} rows. Built once; items are shown or
	 * hidden per {@link Connection.kind} when {@link popup_for} runs. Owns
	 * add / edit / delete / local / refresh using {@link window} and {@link tree}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var menu = new HostTreeMenu(window, tree);
	 * menu.set_parent(list_view);
	 * menu.popup_for(conn, x, y);
	 * }}}
	 */
	public class HostTreeMenu : Gtk.Popover
	{
		private weak MainWindow window;
		private weak HostTree tree;
		private Connection? target;
		private Gtk.Button new_terminal;
		private Gtk.Button new_terminal_here;
		private Gtk.Button close_path;
		private Gtk.Button add_connection_btn;
		private Gtk.Button edit_connection_btn;
		private Gtk.Button refresh_containers_btn;
		private Gtk.Button delete_btn;

		/**
		 * Build all menu buttons (caller sets the popover parent once).
		 *
		 * @param window Main window (dialogs / sessions / config)
		 * @param tree Host tree that owns this menu
		 */
		public HostTreeMenu(MainWindow window, HostTree tree)
		{
			this.window = window;
			this.tree = tree;
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.new_terminal = new Gtk.Button.with_label("New terminal") {
				has_frame = false,
				halign = Gtk.Align.FILL,
				visible = false
			};
			this.new_terminal.clicked.connect(() => {
				this.popdown();
				if (this.target != null) {
					this.window.sessions.open_local(this.target);
				}
			});
			box.append(this.new_terminal);
			this.new_terminal_here = new Gtk.Button.with_label("New terminal here") {
				has_frame = false,
				halign = Gtk.Align.FILL,
				visible = false
			};
			this.new_terminal_here.clicked.connect(() => {
				this.popdown();
				if (this.target != null && this.target.parent != null) {
					var path_term = (Terminal) this.target.sessions.get_item(0);
					this.window.sessions.open_local(this.target.parent, path_term.cwd);
				}
			});
			box.append(this.new_terminal_here);
			this.close_path = new Gtk.Button.with_label("Close") {
				has_frame = false,
				halign = Gtk.Align.FILL,
				visible = false
			};
			this.close_path.clicked.connect(() => {
				this.popdown();
				if (this.target == null) {
					return;
				}
				var term = (Terminal) this.target.sessions.get_item(0);
				var page = this.window.host_stack.pages.get_child_by_name(
					this.target.parent.uuid
				) as HostPage;
				if (page == null) {
					return;
				}
				page.tab_view.close_page(page.tab_view.get_page(term));
				this.window.sessions.focus();
			});
			box.append(this.close_path);
			this.add_connection_btn = new Gtk.Button.with_label("Add connection") {
				has_frame = false,
				halign = Gtk.Align.FILL,
				visible = false
			};
			this.add_connection_btn.clicked.connect(() => {
				this.popdown();
				if (this.target == null) {
					return;
				}
				var group = this.target;
				var dlg = new ConnDialog(this.window);
				dlg.fill(null, group);
				dlg.saved.connect((conn) => {
					this.window.config.by_uuid.set(conn.uuid, conn);
					this.window.config.tree.append(group, conn);
					try {
						this.window.config.save();
					} catch (GLib.Error e) {
						GLib.warning("config save failed: %s", e.message);
					}
				});
				dlg.present(this.window);
			});
			box.append(this.add_connection_btn);
			this.edit_connection_btn = new Gtk.Button.with_label("Edit connection") {
				has_frame = false,
				halign = Gtk.Align.FILL,
				visible = false
			};
			this.edit_connection_btn.clicked.connect(() => {
				this.popdown();
				if (this.target == null || this.target.kind == ConnectionKind.LXC) {
					return;
				}
				var dlg = new ConnDialog(this.window);
				dlg.fill(this.target, null);
				dlg.saved.connect((conn) => {
					try {
						this.window.config.save();
					} catch (GLib.Error e) {
						GLib.warning("config save failed: %s", e.message);
					}
				});
				dlg.present(this.window);
			});
			box.append(this.edit_connection_btn);
			this.refresh_containers_btn = new Gtk.Button.with_label("Refresh containers") {
				has_frame = false,
				halign = Gtk.Align.FILL,
				visible = false
			};
			this.refresh_containers_btn.clicked.connect(() => {
				this.popdown();
				if (this.target == null) {
					return;
				}
				var host = this.target;
				host.refresh_containers.begin(this.window, (obj, res) => {
					try {
						host.apply_containers(
							host.refresh_containers.end(res), this.window
						);
					} catch (JobError e) {
						GLib.warning("fetch hosts failed name=%s: %s",
							host.name, e.message);
					}
				});
			});
			box.append(this.refresh_containers_btn);
			this.delete_btn = new Gtk.Button.with_label("Delete") {
				has_frame = false,
				halign = Gtk.Align.FILL,
				visible = false
			};
			this.delete_btn.clicked.connect(() => {
				this.popdown();
				if (this.target == null) {
					return;
				}
				var conn = this.target;
				var alert = new Adw.AlertDialog("Delete " + conn.name + "?", null);
				alert.add_response("cancel", "Cancel");
				alert.add_response("delete", "Delete");
				alert.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);
				alert.default_response = "cancel";
				alert.close_response = "cancel";
				alert.response.connect((response) => {
					if (response != "delete") {
						return;
					}
					conn.deleted = true;
					this.window.config.tree.remove(conn);
					try {
						this.window.config.save();
					} catch (GLib.Error e) {
						GLib.warning("config save failed: %s", e.message);
					}
				});
				alert.present(this.window);
			});
			box.append(this.delete_btn);
			this.child = box;
		}

		/**
		 * Show or hide items for ``conn`` and popup at the click point.
		 *
		 * @param conn Row that was right-clicked
		 * @param x Click X in the parent widget
		 * @param y Click Y in the parent widget
		 */
		public void popup_for(Connection conn, double x, double y)
		{
			this.target = conn;
			this.new_terminal.visible = conn.kind == ConnectionKind.LOCAL;
			this.new_terminal_here.visible = conn.kind == ConnectionKind.LOCAL_PATH;
			this.close_path.visible = conn.kind == ConnectionKind.LOCAL_PATH;
			this.add_connection_btn.visible = conn.kind == ConnectionKind.GROUP;
			this.edit_connection_btn.visible = conn.kind == ConnectionKind.HOST;
			this.refresh_containers_btn.visible = conn.kind == ConnectionKind.HOST && conn.lxc_host;
			this.delete_btn.visible = conn.kind == ConnectionKind.HOST
				|| conn.kind == ConnectionKind.GROUP
				|| conn.kind == ConnectionKind.LXC;
			this.delete_btn.sensitive = true;
			if (conn.kind == ConnectionKind.GROUP) {
				var can_delete = true;
				foreach (var child in conn.children) {
					if (!child.deleted) {
						can_delete = false;
						break;
					}
				}
				this.delete_btn.sensitive = can_delete;
			}
			this.pointing_to = Gdk.Rectangle() {
				x = (int) x, 
				y = (int) y,
				width = 1, 
				height = 1
			};
			this.popup();
		}
	}
}
