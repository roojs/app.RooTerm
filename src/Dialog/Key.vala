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

namespace RooTerm.Dialog
{
	/**
	 * Create a passphrased private key (passphrase entered twice).
	 * Create mode writes ``~/.ssh/id_ed25519``; replace mode writes the shared
	 * ``identity`` path (``id_ed25519_rooterm``) — reused across hosts when it already exists.
	 */
	public class Key : Adw.Dialog
	{
		private Gtk.PasswordEntry pass_entry;
		private Gtk.PasswordEntry confirm_entry;
		private string identity_path;
		private bool replace;

		/**
		 * Emitted after ``ssh-keygen`` succeeds.
		 *
		 * @param identity Private key path (no ``.pub``)
		 * @param passphrase Passphrase used to encrypt the key
		 */
		public signal void created(string identity, string passphrase);

		/**
		 * Build the passphrase form.
		 *
		 * @param identity Private key path to create (empty → ``~/.ssh/id_ed25519``)
		 * @param replace When true, explain install-then-remove-old as two steps
		 */
		public Key(string identity = "", bool replace = false)
		{
			this.identity_path = identity;
			this.replace = replace;
			this.content_width = 440;
			this.title = replace ? "Replace private key" : "Create private key";

			this.pass_entry = new Gtk.PasswordEntry() {
				show_peek_icon = true,
				hexpand = true
			};
			this.confirm_entry = new Gtk.PasswordEntry() {
				show_peek_icon = true,
				hexpand = true
			};

			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10) {
				margin_top = 16,
				margin_bottom = 16,
				margin_start = 16,
				margin_end = 16
			};
			if (replace) {
				box.append(new Gtk.Label(
"""Create a new passphrased key (stored in the secret store) to replace
the unprotected one. Next we install it on the server. Removing the
old key from the server is a separate step after you verify the new
key works. The local unprotected key is left on disk."""
				) {
					xalign = 0,
					wrap = true
				});
			} else {
				box.append(new Gtk.Label(
"""No ~/.ssh/id_ed25519 or id_rsa found. Create an ed25519 key
protected by a passphrase."""
				) {
					xalign = 0,
					wrap = true
				});
			}
			box.append(new Gtk.Label("Passphrase") { xalign = 0 });
			box.append(this.pass_entry);
			box.append(new Gtk.Label("Confirm passphrase") { xalign = 0 });
			box.append(this.confirm_entry);

			var cancel = new Gtk.Button.with_label("Cancel");
			cancel.clicked.connect(() => {
				this.close();
			});
			var create = new Gtk.Button.with_label(replace ? "Create and continue" : "Create") {
				css_classes = { "suggested-action" }
			};
			create.clicked.connect(() => {
				this.on_create();
			});

			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			header.pack_start(cancel);
			header.pack_end(create);
			var toolbar = new Adw.ToolbarView();
			toolbar.add_top_bar(header);
			toolbar.content = box;
			this.child = toolbar;
		}

		/**
		 * Validate matching non-empty passphrase, run ``ssh-keygen``, emit {@link created}.
		 */
		private void on_create()
		{
			var pass = this.pass_entry.text;
			var confirm = this.confirm_entry.text;
			if (pass.length == 0) {
				this.pass_entry.grab_focus();
				return;
			}
			if (pass != confirm) {
				this.confirm_entry.text = "";
				this.confirm_entry.grab_focus();
				return;
			}
			var home = GLib.Environment.get_home_dir();
			var ssh_dir = GLib.Path.build_filename(home, ".ssh");
			GLib.DirUtils.create_with_parents(ssh_dir, 0700);
			var identity = this.identity_path;
			if (identity.length == 0) {
				identity = GLib.Path.build_filename(ssh_dir, "id_ed25519");
			}
			var pub = identity + ".pub";
			if (GLib.FileUtils.test(pub, GLib.FileTest.IS_REGULAR)
					&& GLib.FileUtils.test(identity, GLib.FileTest.IS_REGULAR)) {
				this.created(identity, pass);
				this.close();
				return;
			}
			string[] argv = {
				"ssh-keygen", "-t", "ed25519", "-f", identity, "-N", pass, "-q"
			};
			string serr;
			int status;
			try {
				GLib.Process.spawn_sync(
					null, argv, null, GLib.SpawnFlags.SEARCH_PATH, null,
					null, out serr, out status
				);
			} catch (GLib.Error e) {
				GLib.warning("ssh-keygen failed: %s", e.message);
				return;
			}
			if (status != 0 || !GLib.FileUtils.test(pub, GLib.FileTest.IS_REGULAR)) {
				GLib.warning("ssh-keygen status=%d stderr=%s", status, serr ?? "");
				return;
			}
			GLib.debug("created %s replace=%d", identity, (int) this.replace);
			this.created(identity, pass);
			this.close();
		}
	}
}
