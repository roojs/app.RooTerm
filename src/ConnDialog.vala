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
		private delegate void KeyNext();

		private Connection target;
		private Connection? parent_group;
		private bool is_new;
		private Gtk.Entry name_entry;
		private Gtk.Entry host_entry;
		private Gtk.Entry port_entry;
		private Gtk.Entry user_entry;
		private Gtk.PasswordEntry pass_entry;
		private Gtk.Label pass_label;
		private Gtk.CheckButton auth_password;
		private Gtk.CheckButton auth_key;
		private Gtk.CheckButton auth_manual;
		private Gtk.Box pass_box;
		private Gtk.CheckButton sudo_check;
		private Gtk.CheckButton lxc_host_check;
		private Gtk.Button fetch_hosts_btn;
		private Gtk.Button setup_key_btn;
		private Gtk.Button upgrade_key_btn;
		private Gtk.Button retire_key_btn;
		private GLib.ListStore forward_store;
		private Gtk.SingleSelection forward_selection;
		private Gtk.ColumnView forward_view;
		private Gtk.Button edit_forward_btn;
		private weak MainWindow window;
		/**
		 * Identity path from a successful ``ssh-copy-id``; applied on Save.
		 */
		private string pending_key_identity = "";
		/**
		 * Staged ``lxc-ls`` names from Fetch hosts; applied on Save only.
		 */
		private string[] pending_lxc_names = {};
		private bool pending_lxc_sync = false;

		/**
		 * Emitted after Save writes fields onto ``target``.
		 *
		 * @param connection The connection that was saved
		 */
		public signal void saved(Connection connection);

		/**
		 * Build the dialog UI (call {@link fill} before presenting).
		 *
		 * @param window Main window (sessions / config for SSH key setup)
		 */
		public ConnDialog(MainWindow window)
		{
			this.window = window;
			this.target = new Connection();
			this.content_width = 560;
			this.content_height = 520;
			this.title = "Connection";

			this.name_entry = new Gtk.Entry() { hexpand = true };
			this.host_entry = new Gtk.Entry() { hexpand = true };
			this.port_entry = new Gtk.Entry() {
				input_purpose = Gtk.InputPurpose.DIGITS,
				hexpand = true
			};
			this.user_entry = new Gtk.Entry() { hexpand = true };
			this.pass_entry = new Gtk.PasswordEntry() {
				show_peek_icon = true,
				hexpand = true
			};

			this.auth_password = new Gtk.CheckButton.with_label("Password") {
				active = true
			};
			this.auth_key = new Gtk.CheckButton.with_label("SSH key") {
				group = this.auth_password,
				visible = false
			};
			this.auth_manual = new Gtk.CheckButton.with_label("Manual") {
				group = this.auth_password
			};
			this.setup_key_btn = new Gtk.Button.with_label("Set up SSH key") {
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER
			};

			this.pass_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
			this.pass_label = new Gtk.Label("Password") { xalign = 0 };
			this.pass_box.append(this.pass_label);
			this.pass_box.append(this.pass_entry);

			var auth_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			auth_box.append(this.auth_password);
			auth_box.append(this.setup_key_btn);
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

			this.sudo_check = new Gtk.CheckButton.with_label("sudo -i after login");
			this.lxc_host_check = new Gtk.CheckButton.with_label("LXC host") {
				sensitive = false
			};
			this.fetch_hosts_btn = new Gtk.Button.with_label("Fetch hosts") {
				halign = Gtk.Align.START,
				visible = false
			};
			this.fetch_hosts_btn.clicked.connect(() => {
				this.target.sudo_after_login = this.sudo_check.active;
				this.target.lxc_host = this.lxc_host_check.active;
				if (this.pass_entry.text.length > 0) {
					this.target.pass = this.pass_entry.text;
				}
				this.close();
				var term = this.target.refresh_containers(this.window, (names) => {
					this.pending_lxc_names = names;
					this.pending_lxc_sync = true;
					GLib.debug("fetch hosts staged count=%d", names.length);
					this.present(this.window);
				});
				term.close_tab.connect(() => {
					this.present(this.window);
				});
			});
			this.setup_key_btn.clicked.connect(() => {
				this.ensure_key(() => {
					this.target.host = this.host_entry.text.strip();
					this.target.user = this.user_entry.text.strip();
					var port = int.parse(this.port_entry.text.strip());
					if (port > 0 && port <= 65535) {
						this.target.port = port;
					}
					if (this.pass_entry.text.length > 0) {
						this.target.pass = this.pass_entry.text;
					}
					this.close();
					var stream = new SshStream();
					stream.install_key = true;
					var term = this.window.sessions.open(this.target, stream);
					term.stream.key_installed.connect((identity) => {
						this.pending_key_identity = identity;
						this.target.auth = "ssh_key";
						this.target.public_key = identity;
						this.setup_key_btn.visible = false;
						this.auth_key.visible = true;
						this.auth_key.active = true;
						try {
							this.window.config.save();
						} catch (GLib.Error e) {
							GLib.warning("config save failed: %s", e.message);
						}
						this.pass_box.visible = this.auth_password.active || this.sudo_check.active;
						this.pass_label.label = this.auth_key.active && this.sudo_check.active
							? "Password (required for sudo)"
							: "Password";
						GLib.debug("ssh key installed identity=%s name=%s", identity, this.target.name);
						GLib.Timeout.add_seconds(2, () => {
							term.close_tab();
							return false;
						});
						this.present(this.window);
					});
					term.close_tab.connect(() => {
						this.present(this.window);
					});
				});
			});
			var sudo_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			sudo_row.append(this.sudo_check);
			sudo_row.append(this.lxc_host_check);
			basic.append(sudo_row);
			basic.append(this.fetch_hosts_btn);
			this.upgrade_key_btn = new Gtk.Button.with_label("Replace with passphrased key") {
				halign = Gtk.Align.START,
				visible = false
			};
			this.retire_key_btn = new Gtk.Button.with_label("Remove old key from server") {
				halign = Gtk.Align.START,
				visible = false
			};
			this.upgrade_key_btn.clicked.connect(() => {
				this.begin_key_upgrade();
			});
			this.retire_key_btn.clicked.connect(() => {
				this.begin_key_retire();
			});
			basic.append(this.upgrade_key_btn);
			basic.append(this.retire_key_btn);

			this.auth_password.toggled.connect(() => {
				this.pass_box.visible = this.auth_password.active || this.sudo_check.active;
				this.pass_label.label = this.auth_key.active && this.sudo_check.active
					? "Password (required for sudo)"
					: "Password";
				if (this.auth_password.active) {
					this.auth_key.visible = false;
					this.setup_key_btn.visible = !this.is_new
						&& this.target != null
						&& this.target.kind != ConnectionKind.LXC;
				}
			});
			this.auth_key.toggled.connect(() => {
				this.pass_box.visible = this.auth_password.active || this.sudo_check.active;
				this.pass_label.label = this.auth_key.active && this.sudo_check.active
					? "Password (required for sudo)"
					: "Password";
				if (this.auth_key.active) {
					this.auth_key.visible = true;
					this.setup_key_btn.visible = false;
				}
			});
			this.auth_manual.toggled.connect(() => {
				this.pass_box.visible = this.auth_password.active || this.sudo_check.active;
				this.pass_label.label = this.auth_key.active && this.sudo_check.active
					? "Password (required for sudo)"
					: "Password";
				if (this.auth_manual.active) {
					this.auth_key.visible = false;
					this.setup_key_btn.visible = !this.is_new
						&& this.target != null
						&& this.target.kind != ConnectionKind.LXC;
				}
			});
			this.sudo_check.toggled.connect(() => {
				this.lxc_host_check.sensitive = this.sudo_check.active;
				if (!this.sudo_check.active) {
					this.lxc_host_check.active = false;
				}
				this.pass_box.visible = this.auth_password.active || this.sudo_check.active;
				this.pass_label.label = this.auth_key.active && this.sudo_check.active
					? "Password (required for sudo)"
					: "Password";
			});
			this.lxc_host_check.toggled.connect(() => {
				this.fetch_hosts_btn.visible = this.lxc_host_check.active;
			});
			this.pass_box.visible = true;

			this.forward_store = new GLib.ListStore(typeof(Forward));

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
				this.on_save();
			});

			var header = new Adw.HeaderBar() {
				title_widget = switcher,
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			header.pack_start(cancel);
			header.pack_end(save);
			var toolbar = new Adw.ToolbarView();
			toolbar.add_top_bar(header);
			toolbar.content = stack;
			this.child = toolbar;
		}

		/**
		 * If neither ``id_ed25519`` nor ``id_rsa`` exists, open {@link KeyDialog}
		 * to create a passphrased key, then call ``next``.
		 *
		 * @param next Continues SSH key setup when a public key is ready
		 */
		private void ensure_key(owned KeyNext next)
		{
			var home = GLib.Environment.get_home_dir();
			var ed = GLib.Path.build_filename(home, ".ssh", "id_ed25519.pub");
			var rsa = GLib.Path.build_filename(home, ".ssh", "id_rsa.pub");
			if (GLib.FileUtils.test(ed, GLib.FileTest.IS_REGULAR)
					|| GLib.FileUtils.test(rsa, GLib.FileTest.IS_REGULAR)) {
				next();
				return;
			}
			var dlg = new KeyDialog();
			dlg.created.connect((identity, passphrase) => {
				this.target.passphrase = passphrase;
				try {
					Secret.password_store_sync(
						new Secret.Schema(
							"org.roojs.rooterm.SshKey", Secret.SchemaFlags.NONE,
							"path", Secret.SchemaAttributeType.STRING
						),
						Secret.COLLECTION_DEFAULT,
						"RooTerm SSH key " + identity,
						passphrase,
						null,
						"path", identity
					);
				} catch (GLib.Error e) {
					GLib.warning("key secret store failed path=%s: %s", identity, e.message);
				}
				next();
			});
			dlg.present(this);
		}

		/**
		 * Step 1: create a new passphrased key, install it, keep {@link Connection.retire_key}
		 * for the old identity until step 2.
		 */
		private void begin_key_upgrade()
		{
			var home = GLib.Environment.get_home_dir();
			var old_identity = this.target.public_key;
			if (old_identity.length == 0) {
				var ed = GLib.Path.build_filename(home, ".ssh", "id_ed25519");
				var rsa = GLib.Path.build_filename(home, ".ssh", "id_rsa");
				if (GLib.FileUtils.test(ed + ".pub", GLib.FileTest.IS_REGULAR)) {
					old_identity = ed;
				} else if (GLib.FileUtils.test(rsa + ".pub", GLib.FileTest.IS_REGULAR)) {
					old_identity = rsa;
				}
			}
			if (old_identity.length == 0) {
				GLib.warning("no identity to replace name=%s", this.target.name);
				return;
			}
			var new_identity = GLib.Path.build_filename(
				home, ".ssh", "id_ed25519_" + this.target.uuid.substring(0, 8)
			);
			var dlg = new KeyDialog(new_identity, true);
			dlg.created.connect((identity, passphrase) => {
				this.target.passphrase = passphrase;
				try {
					Secret.password_store_sync(
						new Secret.Schema(
							"org.roojs.rooterm.SshKey", Secret.SchemaFlags.NONE,
							"path", Secret.SchemaAttributeType.STRING
						),
						Secret.COLLECTION_DEFAULT,
						"RooTerm SSH key " + identity,
						passphrase,
						null,
						"path", identity
					);
				} catch (GLib.Error e) {
					GLib.warning("key secret store failed path=%s: %s", identity, e.message);
				}
				this.target.host = this.host_entry.text.strip();
				this.target.user = this.user_entry.text.strip();
				var port = int.parse(this.port_entry.text.strip());
				if (port > 0 && port <= 65535) {
					this.target.port = port;
				}
				if (this.pass_entry.text.length > 0) {
					this.target.pass = this.pass_entry.text;
				}
				this.close();
				var stream = new SshStream();
				stream.install_key = true;
				stream.install_identity = identity;
				var term = this.window.sessions.open(this.target, stream);
				term.stream.key_installed.connect((installed) => {
					this.target.auth = "ssh_key";
					this.target.retire_key = old_identity;
					this.target.public_key = installed;
					this.pending_key_identity = installed;
					this.setup_key_btn.visible = false;
					this.auth_key.visible = true;
					this.auth_key.active = true;
					this.upgrade_key_btn.visible = false;
					this.retire_key_btn.visible = true;
					try {
						this.window.config.save();
					} catch (GLib.Error e) {
						GLib.warning("config save failed: %s", e.message);
					}
					GLib.debug("key replaced new=%s old=%s name=%s",
						installed, old_identity, this.target.name);
					GLib.Timeout.add_seconds(2, () => {
						term.close_tab();
						return false;
					});
					var done = new Adw.AlertDialog(
						"New key installed",
"""Verify login with the new key works, then use
“Remove old key from server” on this connection."""
					);
					done.add_response("ok", "OK");
					done.default_response = "ok";
					done.close_response = "ok";
					done.response.connect(() => {
						this.present(this.window);
					});
					done.present(this.window);
				});
				term.close_tab.connect(() => {
					this.present(this.window);
				});
			});
			dlg.present(this);
		}

		/**
		 * Step 2: after the new key works, remove the old pubkey from the server.
		 */
		private void begin_key_retire()
		{
			if (this.target.retire_key.length == 0) {
				return;
			}
			var pub_path = this.target.retire_key;
			if (!pub_path.has_suffix(".pub")) {
				pub_path = pub_path + ".pub";
			}
			string pub_line;
			try {
				GLib.FileUtils.get_contents(pub_path, out pub_line);
			} catch (GLib.Error e) {
				GLib.warning("read retire pub failed path=%s: %s", pub_path, e.message);
				return;
			}
			pub_line = pub_line.strip();
			if (pub_line.length == 0) {
				return;
			}
			this.target.host = this.host_entry.text.strip();
			this.target.user = this.user_entry.text.strip();
			var port = int.parse(this.port_entry.text.strip());
			if (port > 0 && port <= 65535) {
				this.target.port = port;
			}
			this.close();
			var stream = new SshStream();
			stream.remove_old_key = true;
			stream.remove_pub_line = pub_line;
			var term = this.window.sessions.open(this.target, stream);
			term.stream.old_key_removed.connect(() => {
				this.target.retire_key = "";
				this.retire_key_btn.visible = false;
				try {
					this.window.config.save();
				} catch (GLib.Error e) {
					GLib.warning("config save failed: %s", e.message);
				}
				GLib.debug("retire_key cleared name=%s", this.target.name);
				GLib.Timeout.add_seconds(2, () => {
					term.close_tab();
					return false;
				});
				this.present(this.window);
			});
			term.close_tab.connect(() => {
				this.present(this.window);
			});
		}

		/**
		 * Validate widgets, write {@link target}, persist secret, emit {@link saved}.
		 */
		private void on_save()
		{
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
			this.target.host = this.host_entry.text.strip();
			this.target.port = port;
			this.target.user = this.user_entry.text.strip();

			if (this.auth_password.active) {
				this.target.auth = "password";
				this.target.pass = this.pass_entry.text;
			} else if (this.auth_key.active) {
				this.target.auth = "ssh_key";
				this.target.pass = this.sudo_check.active ? this.pass_entry.text : "";
				if (this.pending_key_identity.length > 0) {
					this.target.public_key = this.pending_key_identity;
				}
			} else {
				this.target.auth = "manual";
				this.target.pass = "";
			}

			if (this.sudo_check.active && this.target.pass.length == 0) {
				try {
					var existing = Secret.password_lookup_sync(
						new Secret.Schema(
							"org.roojs.rooterm.Connection", Secret.SchemaFlags.NONE,
							"uuid", Secret.SchemaAttributeType.STRING
						),
						null,
						"uuid", this.target.uuid
					);
					if (existing == null || existing.length == 0) {
						this.pass_entry.grab_focus();
						return;
					}
					this.target.pass = existing;
				} catch (GLib.Error e) {
					GLib.warning("secret load failed uuid=%s: %s", this.target.uuid, e.message);
					this.pass_entry.grab_focus();
					return;
				}
			}

			try {
				var schema = new Secret.Schema(
					"org.roojs.rooterm.Connection", Secret.SchemaFlags.NONE,
					"uuid", Secret.SchemaAttributeType.STRING
				);
				var keep_secret = this.target.pass.length > 0
					&& (this.target.auth == "password" || this.sudo_check.active);
				if (keep_secret) {
					Secret.password_store_sync(
						schema,
						Secret.COLLECTION_DEFAULT,
						"RooTerm " + this.target.uuid,
						this.target.pass,
						null,
						"uuid", this.target.uuid
					);
				} else if (this.target.auth != "ssh_key" || !this.sudo_check.active) {
					Secret.password_clear_sync(schema, null, "uuid", this.target.uuid);
				}
			} catch (GLib.Error e) {
				GLib.warning("secret save failed uuid=%s: %s", this.target.uuid, e.message);
			}

			this.target.forwards = new Gee.ArrayList<Forward>();
			for (var i = 0; i < this.forward_store.get_n_items(); i++) {
				var item = this.forward_store.get_item(i) as Forward;
				if (item == null) {
					continue;
				}
				this.target.forwards.add(item);
			}
			this.target.sudo_after_login = this.sudo_check.active;
			this.target.lxc_host = this.lxc_host_check.active;
			if (this.pending_lxc_sync) {
				this.target.apply_containers(this.pending_lxc_names, this.window);
				this.pending_lxc_sync = false;
				this.pending_lxc_names = {};
			}
			this.saved(this.target);

			if (this.target.auth == "ssh_key" && this.target.retire_key.length == 0
					&& this.key_open()) {
				var alert = new Adw.AlertDialog(
					"Unprotected SSH key",
"""This private key has no passphrase. Replace it with a new
passphrased key (stored in the secret store). Installing the new
key and removing the old one from the server are two separate
steps so you can verify the new key works first."""
				);
				alert.add_response("later", "Later");
				alert.add_response("replace", "Replace key…");
				alert.default_response = "replace";
				alert.close_response = "later";
				alert.set_response_appearance("replace", Adw.ResponseAppearance.SUGGESTED);
				alert.response.connect((response) => {
					if (response == "replace") {
						this.begin_key_upgrade();
						return;
					}
					this.close();
				});
				alert.present(this);
				return;
			}
			this.close();
		}

		/**
		 * True when the connection identity exists and accepts an empty passphrase.
		 */
		private bool key_open()
		{
			var identity = this.target.public_key;
			if (identity.length == 0) {
				var home = GLib.Environment.get_home_dir();
				var ed = GLib.Path.build_filename(home, ".ssh", "id_ed25519");
				var rsa = GLib.Path.build_filename(home, ".ssh", "id_rsa");
				if (GLib.FileUtils.test(ed, GLib.FileTest.IS_REGULAR)) {
					identity = ed;
				} else if (GLib.FileUtils.test(rsa, GLib.FileTest.IS_REGULAR)) {
					identity = rsa;
				}
			}
			if (identity.length == 0 || !GLib.FileUtils.test(identity, GLib.FileTest.IS_REGULAR)) {
				return false;
			}
			int status = -1;
			try {
				GLib.Process.spawn_sync(
					null,
					{ "ssh-keygen", "-y", "-f", identity, "-P", "" },
					null,
					GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.STDOUT_TO_DEV_NULL
						| GLib.SpawnFlags.STDERR_TO_DEV_NULL,
					null, null, null, out status
				);
			} catch (GLib.Error e) {
				GLib.warning("ssh-keygen -y failed: %s", e.message);
				return false;
			}
			return status == 0;
		}

		/**
		 * Load add/edit state into the widgets.
		 *
		 * @param edit Existing host to edit, or ``null`` to add
		 * @param parent_group Group for a new host (ignored when editing)
		 */
		public void fill(Connection? edit, Connection? parent_group)
		{
			this.parent_group = parent_group;
			this.is_new = edit == null;
			this.pending_lxc_names = {};
			this.pending_lxc_sync = false;
			this.pending_key_identity = "";
			if (edit != null) {
				this.target = edit;
				this.title = "Edit connection";
			} else {
				this.target = new Connection() {
					uuid = GLib.Uuid.string_random(),
					kind = ConnectionKind.HOST,
					parent_uuid = parent_group != null ? parent_group.uuid : "",
					port = 22,
					auth = "password",
					user = GLib.Environment.get_user_name()
				};
				this.title = "Add connection";
			}

			this.name_entry.text = this.target.name;
			this.host_entry.text = this.target.host;
			this.port_entry.text = this.target.port.to_string();
			this.user_entry.text = this.target.user;

			var pass_text = this.target.pass;
			if (edit != null && pass_text.length == 0 && this.target.auth != "manual"
					&& ((this.target.auth != "ssh_key" && this.target.auth != "publickey")
						|| this.target.sudo_after_login)) {
				try {
					var pass = Secret.password_lookup_sync(
						new Secret.Schema(
							"org.roojs.rooterm.Connection", Secret.SchemaFlags.NONE,
							"uuid", Secret.SchemaAttributeType.STRING
						),
						null,
						"uuid", this.target.uuid
					);
					pass_text = pass != null ? pass : "";
				} catch (GLib.Error e) {
					GLib.warning("secret load failed uuid=%s: %s", this.target.uuid, e.message);
				}
			}
			this.pass_entry.text = pass_text;

			var using_key = this.target.auth == "ssh_key"
				|| this.target.auth == "publickey";
			this.setup_key_btn.visible = !this.is_new && this.target.kind != ConnectionKind.LXC && !using_key;
			this.auth_key.visible = using_key;
			if (using_key) {
				this.auth_key.active = true;
			} else if (this.target.auth == "manual") {
				this.auth_manual.active = true;
			} else {
				this.auth_password.active = true;
			}
			this.sudo_check.active = this.target.sudo_after_login;
			this.sudo_check.visible = this.target.kind != ConnectionKind.LXC;
			this.lxc_host_check.active = this.target.lxc_host && this.target.sudo_after_login;
			this.lxc_host_check.sensitive = this.sudo_check.active;
			this.lxc_host_check.visible = this.target.kind != ConnectionKind.LXC;
			this.fetch_hosts_btn.visible = this.lxc_host_check.active && !this.is_new;
			this.retire_key_btn.visible = using_key && this.target.retire_key.length > 0;
			this.upgrade_key_btn.visible = using_key && this.target.retire_key.length == 0
				&& this.key_open() && !this.is_new && this.target.kind != ConnectionKind.LXC;
			this.pending_key_identity = "";
			this.pass_box.visible = this.auth_password.active || this.sudo_check.active;
			this.pass_label.label =
				(this.target.auth == "ssh_key" || this.target.auth == "publickey")
				&& this.target.sudo_after_login
					? "Password (required for sudo)"
					: "Password";

			this.forward_store.remove_all();
			foreach (var fwd in this.target.forwards) {
				this.forward_store.append(new Forward() {
					local_host = fwd.local_host,
					local_port = fwd.local_port,
					remote_host = fwd.remote_host,
					remote_port = fwd.remote_port
				});
			}
		}
	}
}
