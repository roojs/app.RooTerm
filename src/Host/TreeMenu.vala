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
	 * Context menu for {@link Tree} rows. Owns one {@link Gtk.PopoverMenu};
	 * {@link popup_for} rebuilds the {@link GLib.Menu} for the row’s
	 * {@link Connection.kind} (``null`` = blank space → Add group).
	 * Actions live on the ``tree`` action group.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var menu = new TreeMenu(window, tree);
	 * menu.set_parent(list_view);
	 * menu.popup_for(conn, x, y);
	 * }}}
	 */
	public class TreeMenu : GLib.Object
	{
		/**
		 * The real menu widget ({@link Gtk.PopoverMenu} is not subclassable).
		 */
		public Gtk.PopoverMenu menu { get; private set; }
		private weak RooTerm.MainWindow window;
		private weak Tree tree;
		private Connection? target;
		private GLib.SimpleAction delete_action;

		/**
		 * Register ``tree.*`` actions (caller sets the popover parent once).
		 *
		 * @param window Main window (dialogs / sessions / config)
		 * @param tree Host tree that owns this menu
		 */
		public TreeMenu(RooTerm.MainWindow window, Tree tree)
		{
			this.window = window;
			this.tree = tree;
			this.menu = new Gtk.PopoverMenu.from_model(new GLib.Menu()) {
				has_arrow = false
			};
			var group = new GLib.SimpleActionGroup();
			var new_terminal = new GLib.SimpleAction("new-terminal", null);
			new_terminal.activate.connect(() => {
				if (this.target != null) {
					this.window.sessions.open_local(this.target);
				}
			});
			group.add_action(new_terminal);
			var new_terminal_here = new GLib.SimpleAction("new-terminal-here", null);
			new_terminal_here.activate.connect(() => {
				if (this.target != null && this.target.parent != null) {
					var path_term = (Terminal.Base) this.target.sessions.get_item(0);
					this.window.sessions.open_local(this.target.parent, path_term.cwd);
				}
			});
			group.add_action(new_terminal_here);
			var close_path = new GLib.SimpleAction("close", null);
			close_path.activate.connect(() => {
				if (this.target == null) {
					return;
				}
				var term = (Terminal.Base) this.target.sessions.get_item(0);
				var page = this.window.host_stack.pages.get_child_by_name(
					this.target.parent.uuid
				) as Page;
				if (page == null) {
					return;
				}
				page.tab_view.close_page(page.tab_view.get_page(term));
				this.window.sessions.focus();
			});
			group.add_action(close_path);
			var add_connection = new GLib.SimpleAction("add-connection", null);
			add_connection.activate.connect(() => {
				if (this.target == null) {
					return;
				}
				this.window.connection_editor.fill(null, this.target);
				this.window.dbus.call("Show", new GLib.Variant("(s)", "connection"));
			});
			group.add_action(add_connection);
			var add_group = new GLib.SimpleAction("add-group", null);
			add_group.activate.connect(() => {
				var entry = new Gtk.Entry() {
					text = "New group",
					hexpand = true,
					activates_default = true
				};
				var alert = new Adw.AlertDialog("Add group", null);
				alert.extra_child = entry;
				alert.add_response("cancel", "Cancel");
				alert.add_response("add", "Add");
				alert.default_response = "add";
				alert.close_response = "cancel";
				alert.set_response_appearance("add", Adw.ResponseAppearance.SUGGESTED);
				alert.response.connect((response) => {
					if (response != "add") {
						return;
					}
					var name = entry.text.strip();
					if (name.length == 0) {
						name = "New group";
					}
					var conn = new Connection() {
						uuid = GLib.Uuid.string_random(),
						name = name,
						kind = ConnectionKind.GROUP
					};
					this.window.config.by_uuid.set(conn.uuid, conn);
					this.window.config.tree.append(null, conn);
					this.window.config.save();
				});
				alert.present(this.window);
			});
			group.add_action(add_group);
			var edit_connection = new GLib.SimpleAction("edit-connection", null);
			edit_connection.activate.connect(() => {
				if (this.target == null || this.target.kind == ConnectionKind.LXC) {
					return;
				}
				this.window.connection_editor.fill(this.target, null);
				this.window.dbus.call("Show", new GLib.Variant("(s)", "connection"));
			});
			group.add_action(edit_connection);
			var refresh_containers = new GLib.SimpleAction("refresh-containers", null);
			refresh_containers.activate.connect(() => {
				if (this.target == null) {
					return;
				}
				var host = this.target;
				host.refresh_containers.begin(this.window, (obj, res) => {
					try {
						host.apply_containers(
							host.refresh_containers.end(res), this.window
						);
					} catch (Jobs.Error e) {
						GLib.warning("fetch hosts failed name=%s: %s",
							host.name, e.message);
					}
				});
			});
			group.add_action(refresh_containers);
			this.delete_action = new GLib.SimpleAction("delete", null);
			this.delete_action.activate.connect(() => {
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
					// reverse: close_in(0) removes from sessions synchronously;
					// close before kill so EXITED handlers cannot re-arm a countdown
					for (var i = (int) conn.sessions.get_n_items() - 1; i >= 0; i--) {
						var term = (Terminal.Base) conn.sessions.get_item(i);
						var pid = term.child_pid;
						term.close_in(0);
						if (pid > 0) {
							Posix.kill(pid, Posix.Signal.TERM);
						}
					}
					this.window.config.save();
				});
				alert.present(this.window);
			});
			group.add_action(this.delete_action);
			this.menu.insert_action_group("tree", group);
			this.menu.notify["visible"].connect(() => {
				if (!this.menu.visible) {
					this.tree.menu_target = null;
				}
			});
		}

		/**
		 * Parent the popover once (usually the tree {@link Gtk.ListView}).
		 *
		 * @param parent Widget that owns the click coordinates
		 */
		public void set_parent(Gtk.Widget parent)
		{
			this.menu.set_parent(parent);
		}

		/**
		 * Rebuild items for ``conn`` and popup at the click point.
		 * ``null`` is blank space (Add group only).
		 *
		 * @param conn Row that was right-clicked, or ``null`` for empty area
		 * @param x Click X in the parent widget
		 * @param y Click Y in the parent widget
		 */
		public void popup_for(Connection? conn, double x, double y)
		{
			this.target = conn;
			this.tree.menu_target = conn;
			var model = new GLib.Menu();
			if (conn == null) {
				var add_group = new GLib.MenuItem("Add group", "tree.add-group");
				add_group.set_icon(new GLib.ThemedIcon("folder-new-symbolic"));
				model.append_item(add_group);
				this.menu.menu_model = model;
				this.menu.pointing_to = Gdk.Rectangle() {
					x = (int) x,
					y = (int) y,
					width = 1,
					height = 1
				};
				this.menu.popup();
				return;
			}
			switch (conn.kind) {
				case ConnectionKind.LOCAL:
					var item = new GLib.MenuItem("New terminal", "tree.new-terminal");
					item.set_icon(new GLib.ThemedIcon("utilities-terminal-symbolic"));
					model.append_item(item);
					break;

				case ConnectionKind.LOCAL_PATH:
					var here = new GLib.MenuItem("New terminal here", "tree.new-terminal-here");
					here.set_icon(new GLib.ThemedIcon("utilities-terminal-symbolic"));
					model.append_item(here);
					var close_item = new GLib.MenuItem("Close", "tree.close");
					close_item.set_icon(new GLib.ThemedIcon("window-close-symbolic"));
					model.append_item(close_item);
					break;

				case ConnectionKind.GROUP:
					var add = new GLib.MenuItem("Add connection", "tree.add-connection");
					add.set_icon(new GLib.ThemedIcon("list-add-symbolic"));
					model.append_item(add);
					var del_group = new GLib.MenuItem("Delete", "tree.delete");
					del_group.set_icon(new GLib.ThemedIcon("user-trash-symbolic"));
					model.append_item(del_group);
					var can_delete = true;
					foreach (var child in conn.children) {
						if (!child.deleted) {
							can_delete = false;
							break;
						}
					}
					this.delete_action.set_enabled(can_delete);
					break;

				case ConnectionKind.HOST:
					var edit = new GLib.MenuItem("Edit connection", "tree.edit-connection");
					edit.set_icon(new GLib.ThemedIcon("document-edit-symbolic"));
					model.append_item(edit);
					if (conn.lxc_host) {
						var refresh = new GLib.MenuItem("Refresh containers", "tree.refresh-containers");
						refresh.set_icon(new GLib.ThemedIcon("view-refresh-symbolic"));
						model.append_item(refresh);
					}
					var del_host = new GLib.MenuItem("Delete", "tree.delete");
					del_host.set_icon(new GLib.ThemedIcon("user-trash-symbolic"));
					model.append_item(del_host);
					this.delete_action.set_enabled(true);
					break;

				case ConnectionKind.LXC:
					var del_lxc = new GLib.MenuItem("Delete", "tree.delete");
					del_lxc.set_icon(new GLib.ThemedIcon("user-trash-symbolic"));
					model.append_item(del_lxc);
					this.delete_action.set_enabled(true);
					break;
			}
			this.menu.menu_model = model;
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
