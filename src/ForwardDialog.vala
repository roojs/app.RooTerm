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
	 * Add / edit one {@link Forward} (local and remote host + port).
	 */
	public class ForwardDialog : Adw.Dialog
	{
		private Gtk.Entry local_host;
		private Gtk.Entry local_port;
		private Gtk.Entry remote_host;
		private Gtk.Entry remote_port;
		private Forward draft;

		/**
		 * Emitted when Apply succeeds with the edited draft.
		 *
		 * @param forward The forward to keep (same instance as constructed)
		 */
		public signal void applied(Forward forward);

		/**
		 * Build an add/edit dialog for ``forward`` (caller owns the object).
		 *
		 * @param forward Forward to edit in place on apply
		 * @param title Dialog title (``Add forward`` / ``Edit forward``)
		 */
		public ForwardDialog(Forward forward, string title = "Edit forward")
		{
			this.draft = forward;
			this.content_width = 420;
			this.title = title;

			this.local_host = new Gtk.Entry() {
				text = forward.local_host,
				hexpand = true
			};
			this.local_port = new Gtk.Entry() {
				text = forward.local_port > 0 ? forward.local_port.to_string() : "",
				input_purpose = Gtk.InputPurpose.DIGITS,
				hexpand = true
			};
			this.remote_host = new Gtk.Entry() {
				text = forward.remote_host,
				hexpand = true
			};
			this.remote_port = new Gtk.Entry() {
				text = forward.remote_port > 0 ? forward.remote_port.to_string() : "",
				input_purpose = Gtk.InputPurpose.DIGITS,
				hexpand = true
			};

			var grid = new Gtk.Grid() {
				column_spacing = 12,
				row_spacing = 10,
				margin_top = 16,
				margin_bottom = 16,
				margin_start = 16,
				margin_end = 16
			};
			grid.attach(new Gtk.Label("Local address") { xalign = 0 }, 0, 0, 1, 1);
			grid.attach(this.local_host, 1, 0, 1, 1);
			grid.attach(new Gtk.Label("Local port") { xalign = 0 }, 0, 1, 1, 1);
			grid.attach(this.local_port, 1, 1, 1, 1);
			grid.attach(new Gtk.Label("Remote address") { xalign = 0 }, 0, 2, 1, 1);
			grid.attach(this.remote_host, 1, 2, 1, 1);
			grid.attach(new Gtk.Label("Remote port") { xalign = 0 }, 0, 3, 1, 1);
			grid.attach(this.remote_port, 1, 3, 1, 1);

			var cancel = new Gtk.Button.with_label("Cancel");
			cancel.clicked.connect(() => {
				this.close();
			});
			var apply = new Gtk.Button.with_label("Apply") {
				css_classes = { "suggested-action" }
			};
			apply.clicked.connect(() => {
				var lp = int.parse(this.local_port.text.strip());
				var rp = int.parse(this.remote_port.text.strip());
				if (this.local_host.text.strip().length == 0 || lp <= 0 || lp > 65535) {
					return;
				}
				if (this.remote_host.text.strip().length == 0 || rp <= 0 || rp > 65535) {
					return;
				}
				this.draft.local_host = this.local_host.text.strip();
				this.draft.local_port = lp;
				this.draft.remote_host = this.remote_host.text.strip();
				this.draft.remote_port = rp;
				this.applied(this.draft);
				this.close();
			});

			var header = new Adw.HeaderBar();
			header.pack_start(cancel);
			header.pack_end(apply);
			var toolbar = new Adw.ToolbarView();
			toolbar.add_top_bar(header);
			toolbar.content = grid;
			this.child = toolbar;
		}
	}
}
