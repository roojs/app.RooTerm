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
	 * Add / edit a host {@link Connection}: Basic + Port forwarding tabs.
	 * Save applies in memory (JSON / keyring persist is Phase 9).
	 */
	public class ConnDialog : Adw.Dialog
	{
		private Connection target;
		private Connection? parent_group;
		private bool is_new;
		private Gtk.Entry name_entry;
		private Gtk.Entry host_entry;
		private Gtk.Entry port_entry;
		private Gtk.Entry user_entry;
		private Gtk.PasswordEntry pass_entry;
		private Gtk.CheckButton auth_password;
		private Gtk.CheckButton auth_key;
		private Gtk.CheckButton auth_manual;
		private Gtk.Box pass_box;
		private GLib.ListStore forward_store;
		private Gtk.SingleSelection forward_selection;
		private Gtk.ColumnView forward_view;
		private Gtk.Button edit_forward_btn;

		/**
		 * Emitted after Save writes fields onto ``target``.
		 *
		 * @param connection The connection that was saved
		 */
		public signal void saved(Connection connection);

		/**
		 * Add a host under ``parent_group``, or edit ``edit`` when non-null.
		 *
		 * @param edit Existing host to edit, or ``null`` to add
		 * @param parent_group Group for a new host (ignored when editing)
		 */
		public ConnDialog(Connection? edit, Connection? parent_group)
		{
			this.parent_group = parent_group;
			this.content_width = 560;
			this.content_height = 520;
			this.is_new = edit == null;
			if (edit != null) {
				this.target = edit;
				this.title = "Edit connection";
			} else {
				this.target = new Connection() {
					uuid = GLib.Uuid.string_random(),
					is_group = false,
					parent_uuid = parent_group != null ? parent_group.uuid : "",
					port = 22,
					auth_type = "password",
					user = GLib.Environment.get_user_name()
				};
				this.title = "Add connection";
			}

			this.name_entry = new Gtk.Entry() { text = this.target.name, hexpand = true };
			this.host_entry = new Gtk.Entry() { text = this.target.ip, hexpand = true };
			this.port_entry = new Gtk.Entry() {
				text = this.target.port.to_string(),
				input_purpose = Gtk.InputPurpose.DIGITS,
				hexpand = true
			};
			this.user_entry = new Gtk.Entry() { text = this.target.user, hexpand = true };
			this.pass_entry = new Gtk.PasswordEntry() {
				text = this.target.pass,
				show_peek_icon = true,
				hexpand = true
			};

			this.auth_password = new Gtk.CheckButton.with_label("Password");
			this.auth_key = new Gtk.CheckButton.with_label("SSH key") {
				group = this.auth_password
			};
			this.auth_manual = new Gtk.CheckButton.with_label("Manual") {
				group = this.auth_password
			};
			if (this.target.auth_type == "publickey" || this.target.auth_type == "ssh_key") {
				this.auth_key.active = true;
			} else if (this.target.auth_type == "manual") {
				this.auth_manual.active = true;
			} else {
				this.auth_password.active = true;
			}

			this.pass_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
			this.pass_box.append(new Gtk.Label("Password") { xalign = 0 });
			this.pass_box.append(this.pass_entry);

			var auth_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			auth_box.append(this.auth_password);
			auth_box.append(this.auth_key);
			auth_box.append(this.auth_manual);

			var basic = new Gtk.Box(Gtk.Orientation.VERTICAL, 10) {
				margin_top = 16,
				margin_bottom = 16,
				margin_start = 16,
				margin_end = 16
			};
			basic.append(new Gtk.Label("Name") { xalign = 0 });
			basic.append(this.name_entry);
			basic.append(new Gtk.Label("Hostname") { xalign = 0 });
			basic.append(this.host_entry);
			basic.append(new Gtk.Label("Port") { xalign = 0 });
			basic.append(this.port_entry);
			basic.append(new Gtk.Label("Auth") { xalign = 0 });
			basic.append(auth_box);
			basic.append(new Gtk.Label("User") { xalign = 0 });
			basic.append(this.user_entry);
			basic.append(this.pass_box);

			this.auth_password.toggled.connect(() => {
				this.pass_box.visible = this.auth_password.active;
			});
			this.auth_key.toggled.connect(() => {
				this.pass_box.visible = this.auth_password.active;
			});
			this.auth_manual.toggled.connect(() => {
				this.pass_box.visible = this.auth_password.active;
			});
			this.pass_box.visible = this.auth_password.active;

			this.forward_store = new GLib.ListStore(typeof(Forward));
			foreach (var fwd in this.target.forwards) {
				this.forward_store.append(new Forward() {
					local_host = fwd.local_host,
					local_port = fwd.local_port,
					remote_host = fwd.remote_host,
					remote_port = fwd.remote_port
				});
			}

			this.forward_view = new Gtk.ColumnView(null) {
				hexpand = true,
				vexpand = true,
				reorderable = false,
				show_column_separators = true,
				show_row_separators = true
			};
			this.forward_view.add_css_class("data-table");

			var local_host_factory = new Gtk.SignalListItemFactory();
			local_host_factory.setup.connect((obj) => {
				((Gtk.ListItem) obj).child = new Gtk.Label("") { xalign = 0, hexpand = true };
			});
			local_host_factory.bind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var label = list_item.child as Gtk.Label;
				var fwd = list_item.item as Forward;
				if (label == null || fwd == null) {
					return;
				}
				label.label = fwd.local_host;
			});
			var local_host_col = new Gtk.ColumnViewColumn("Local address", local_host_factory) {
				expand = true,
				resizable = true
			};
			local_host_col.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Forward), null, "local-host")
			);
			this.forward_view.append_column(local_host_col);

			var local_port_factory = new Gtk.SignalListItemFactory();
			local_port_factory.setup.connect((obj) => {
				((Gtk.ListItem) obj).child = new Gtk.Label("") { xalign = 0, hexpand = true };
			});
			local_port_factory.bind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var label = list_item.child as Gtk.Label;
				var fwd = list_item.item as Forward;
				if (label == null || fwd == null) {
					return;
				}
				label.label = fwd.local_port.to_string();
			});
			var local_port_col = new Gtk.ColumnViewColumn("Local port", local_port_factory) {
				expand = true,
				resizable = true
			};
			local_port_col.sorter = new Gtk.NumericSorter(
				new Gtk.PropertyExpression(typeof(Forward), null, "local-port")
			);
			this.forward_view.append_column(local_port_col);

			var remote_host_factory = new Gtk.SignalListItemFactory();
			remote_host_factory.setup.connect((obj) => {
				((Gtk.ListItem) obj).child = new Gtk.Label("") { xalign = 0, hexpand = true };
			});
			remote_host_factory.bind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var label = list_item.child as Gtk.Label;
				var fwd = list_item.item as Forward;
				if (label == null || fwd == null) {
					return;
				}
				label.label = fwd.remote_host;
			});
			var remote_host_col = new Gtk.ColumnViewColumn("Remote address", remote_host_factory) {
				expand = true,
				resizable = true
			};
			remote_host_col.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Forward), null, "remote-host")
			);
			this.forward_view.append_column(remote_host_col);

			var remote_port_factory = new Gtk.SignalListItemFactory();
			remote_port_factory.setup.connect((obj) => {
				((Gtk.ListItem) obj).child = new Gtk.Label("") { xalign = 0, hexpand = true };
			});
			remote_port_factory.bind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var label = list_item.child as Gtk.Label;
				var fwd = list_item.item as Forward;
				if (label == null || fwd == null) {
					return;
				}
				label.label = fwd.remote_port.to_string();
			});
			var remote_port_col = new Gtk.ColumnViewColumn("Remote port", remote_port_factory) {
				expand = true,
				resizable = true
			};
			remote_port_col.sorter = new Gtk.NumericSorter(
				new Gtk.PropertyExpression(typeof(Forward), null, "remote-port")
			);
			this.forward_view.append_column(remote_port_col);

			var sorted = new Gtk.SortListModel(this.forward_store, this.forward_view.sorter);
			this.forward_selection = new Gtk.SingleSelection(sorted) {
				autoselect = false,
				can_unselect = true
			};
			this.forward_view.model = this.forward_selection;

			var add_btn = new Gtk.Button.with_label("Add");
			this.edit_forward_btn = new Gtk.Button.with_label("Edit") { sensitive = false };
			var del_btn = new Gtk.Button.with_label("Delete") { sensitive = false };
			this.forward_selection.notify["selected"].connect(() => {
				var has = this.forward_selection.selected != Gtk.INVALID_LIST_POSITION;
				this.edit_forward_btn.sensitive = has;
				del_btn.sensitive = has;
			});
			add_btn.clicked.connect(() => {
				var draft = new Forward();
				var dlg = new ForwardDialog(draft, "Add forward");
				dlg.applied.connect((fwd) => {
					for (var i = 0; i < this.forward_store.get_n_items(); i++) {
						var other = this.forward_store.get_item(i) as Forward;
						if (other == null) {
							continue;
						}
						if (other.local_port == fwd.local_port && other.local_host == fwd.local_host) {
							return;
						}
					}
					this.forward_store.append(fwd);
				});
				dlg.present(this);
			});
			this.edit_forward_btn.clicked.connect(() => {
				var fwd = this.forward_selection.selected_item as Forward;
				if (fwd == null) {
					return;
				}
				var copy = new Forward() {
					local_host = fwd.local_host,
					local_port = fwd.local_port,
					remote_host = fwd.remote_host,
					remote_port = fwd.remote_port
				};
				var dlg = new ForwardDialog(copy, "Edit forward");
				dlg.applied.connect((edited) => {
					uint pos;
					if (!this.forward_store.find(fwd, out pos)) {
						return;
					}
					for (var i = 0; i < this.forward_store.get_n_items(); i++) {
						if (i == (int) pos) {
							continue;
						}
						var other = this.forward_store.get_item(i) as Forward;
						if (other == null) {
							continue;
						}
						if (other.local_port == edited.local_port && other.local_host == edited.local_host) {
							return;
						}
					}
					fwd.local_host = edited.local_host;
					fwd.local_port = edited.local_port;
					fwd.remote_host = edited.remote_host;
					fwd.remote_port = edited.remote_port;
					this.forward_store.items_changed(pos, 1, 1);
				});
				dlg.present(this);
			});
			del_btn.clicked.connect(() => {
				var fwd = this.forward_selection.selected_item as Forward;
				if (fwd == null) {
					return;
				}
				uint pos;
				if (!this.forward_store.find(fwd, out pos)) {
					return;
				}
				this.forward_store.remove(pos);
			});
			this.forward_view.activate.connect((pos) => {
				this.forward_selection.selected = pos;
				this.edit_forward_btn.clicked();
			});

			var left_btns = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			left_btns.append(add_btn);
			left_btns.append(this.edit_forward_btn);
			var fwd_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_bottom = 8
			};
			fwd_bar.append(left_btns);
			fwd_bar.append(new Gtk.Label("") { hexpand = true });
			fwd_bar.append(del_btn);

			var forwards_page = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			forwards_page.append(fwd_bar);
			forwards_page.append(new Gtk.ScrolledWindow() {
				child = this.forward_view,
				hexpand = true,
				vexpand = true,
				min_content_height = 220
			});

			var stack = new Gtk.Stack() { hexpand = true, vexpand = true };
			stack.add_titled(basic, "basic", "Basic");
			stack.add_titled(forwards_page, "forwards", "Port forwarding");
			var switcher = new Gtk.StackSwitcher() { stack = stack };

			var cancel = new Gtk.Button.with_label("Cancel");
			cancel.clicked.connect(() => {
				this.close();
			});
			var save = new Gtk.Button.with_label("Save") {
				css_classes = { "suggested-action" }
			};
			save.clicked.connect(() => {
				if (this.name_entry.text.strip().length == 0) {
					return;
				}
				if (this.host_entry.text.strip().length == 0) {
					return;
				}
				var port = int.parse(this.port_entry.text.strip());
				if (port <= 0 || port > 65535) {
					return;
				}
				this.target.name = this.name_entry.text.strip();
				this.target.ip = this.host_entry.text.strip();
				this.target.port = port;
				this.target.user = this.user_entry.text.strip();
				if (this.auth_password.active) {
					this.target.auth_type = "password";
					this.target.pass = this.pass_entry.text;
				} else if (this.auth_key.active) {
					this.target.auth_type = "ssh_key";
					this.target.pass = "";
					this.target.public_key = "";
				} else {
					this.target.auth_type = "manual";
					this.target.pass = "";
				}
				this.target.forwards = new Gee.ArrayList<Forward>();
				for (var i = 0; i < this.forward_store.get_n_items(); i++) {
					var item = this.forward_store.get_item(i) as Forward;
					if (item == null) {
						continue;
					}
					this.target.forwards.add(item);
				}
				if (this.is_new && this.parent_group != null) {
					this.parent_group.children.add(this.target);
				}
				this.saved(this.target);
				this.close();
			});

			var header = new Adw.HeaderBar() {
				title_widget = switcher
			};
			header.pack_start(cancel);
			header.pack_end(save);
			var toolbar = new Adw.ToolbarView();
			toolbar.add_top_bar(header);
			toolbar.content = stack;
			this.child = toolbar;
		}
	}
}
