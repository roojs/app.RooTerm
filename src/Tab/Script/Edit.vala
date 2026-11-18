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

namespace RooTerm.Tab.Script
{
	/**
	 * Edit one {@link RooTerm.SQT.Script} inside {@link RooTerm.Dialog.Script}.
	 *
	 * Nickname, the commands to run, an optional success criteria
	 * line, and a run-as-root tick on the nickname row. Run/Test is
	 * the header button. It saves, then opens the host picker without
	 * clearing its ticks. Save sits on the bottom and writes the row
	 * without leaving. A ticked save runs ``pkexec /usr/bin/true``
	 * first. A dismissed or failed check does not write the row.
	 * {@link load} is a new visit: the saved row is shown and the
	 * host ticks are cleared.
	 *
	 * == Example ==
	 *
	 * {{{
	 * sender.edit.load(row);
	 * sender.show_page(RooTerm.Dialog.Script.Page.EDIT);
	 * }}}
	 */
	public class Edit : Gtk.Box
	{
		private weak RooTerm.Dialog.Script sender;
		/**
		 * Command being edited. Id 0 is a new command.
		 */
		public RooTerm.SQT.Script row {
			get; set; default = new RooTerm.SQT.Script();
		}
		/**
		 * Header Run/Test button. The window packs it on this page.
		 */
		public Gtk.Button run_btn;
		private Gtk.Entry path_entry;
		private Gtk.TextView body;
		private Gtk.Entry success_entry;
		private Gtk.CheckButton root_check;
		private Gtk.Button delete_btn;
		/**
		 * True while ``pkexec`` is waiting for the keyboard.
		 */
		private bool authorizing = false;

		/**
		 * @param sender script sender window
		 */
		public Edit(RooTerm.Dialog.Script sender)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				hexpand: true,
				vexpand: true
			);
			this.sender = sender;
			this.path_entry = new Gtk.Entry() {
				hexpand = true
			};
			this.body = new Gtk.TextView() {
				monospace = true,
				hexpand = true,
				vexpand = true,
				wrap_mode = Gtk.WrapMode.WORD_CHAR,
				left_margin = 8,
				right_margin = 8,
				top_margin = 8,
				bottom_margin = 8
			};
			var path_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_start = 16,
				margin_end = 16,
				margin_top = 16
			};
			var nickname = new Gtk.Label("nickname") {
				xalign = 0
			};
			path_row.append(nickname);
			path_row.append(this.path_entry);
			this.root_check = new Gtk.CheckButton.with_label("Run as root") {
				valign = Gtk.Align.CENTER
			};
			path_row.append(this.root_check);
			var command_title = new Gtk.Label("Command to Run") {
				xalign = 0,
				margin_start = 16,
				margin_end = 16,
				margin_top = 16
			};
			command_title.add_css_class("heading");
			var guidance = new Gtk.Label("These are the commands to be sent. " +
				"We wait for the prompt after each line break, so you can run multiple commands.") {
				xalign = 0,
				wrap = true,
				margin_start = 16,
				margin_end = 16,
				margin_top = 6
			};
			guidance.add_css_class("dim-label");
			var scrolled = new Gtk.ScrolledWindow() {
				child = this.body,
				hexpand = true,
				vexpand = true,
				margin_start = 16,
				margin_end = 16,
				margin_top = 12
			};
			var success_title = new Gtk.Label("Success criteria") {
				xalign = 0,
				margin_start = 16,
				margin_end = 16,
				margin_top = 12
			};
			success_title.add_css_class("heading");
			var success_hint = new Gtk.Label("Use this to validate completion or success. " +
				"To check a command worked, add && echo \"SUCCEEDED\" at the end of it " +
				"and use SUCCEEDED here.") {
				xalign = 0,
				wrap = true,
				margin_start = 16,
				margin_end = 16,
				margin_top = 6
			};
			success_hint.add_css_class("dim-label");
			this.success_entry = new Gtk.Entry() {
				hexpand = true
			};
			var success_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_start = 16,
				margin_end = 16,
				margin_top = 6
			};
			success_row.append(this.success_entry);
			this.delete_btn = new Gtk.Button.with_label("Delete") {
				css_classes = { "destructive-action" },
				visible = false
			};
			this.delete_btn.clicked.connect(() => {
				var alert = new Adw.AlertDialog("Delete " + this.row.path + "?", null) {
					default_response = "cancel",
					close_response = "cancel"
				};
				alert.add_response("cancel", "Cancel");
				alert.add_response("delete", "Delete");
				alert.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);
				alert.response.connect((response) => {
					if (response != "delete") {
						return;
					}
					this.sender.store.remove(this.row);
					this.sender.show_page(RooTerm.Dialog.Script.Page.LIST);
				});
				alert.present(this.sender);
			});
			this.run_btn = new Gtk.Button.with_label("Run/Test") {
				css_classes = { "suggested-action" }
			};
			this.run_btn.clicked.connect(() => {
				this.on_save_click(true);
			});
			var save = new Gtk.Button.with_label("Save");
			save.clicked.connect(() => {
				this.on_save_click(false);
			});
			var bottom = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_start = 16,
				margin_end = 16,
				margin_top = 12,
				margin_bottom = 16
			};
			bottom.append(this.delete_btn);
			bottom.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			bottom.append(save);
			this.append(path_row);
			this.append(command_title);
			this.append(guidance);
			this.append(scrolled);
			this.append(success_title);
			this.append(success_hint);
			this.append(success_row);
			this.append(bottom);
		}

		/**
		 * Save click. ''testing'' opens the host picker and stays in
		 * this visit, so the ticks are kept.
		 *
		 * An empty nickname or a bad regex does not save. Run as root
		 * asks PolicyKit before the row is written.
		 *
		 * @param testing true from Run/Test
		 */
		private void on_save_click(bool testing)
		{
			if (this.authorizing) {
				return;
			}
			if (this.path_entry.text.strip().length == 0) {
				return;
			}
			var pattern = this.success_entry.text.strip();
			if (pattern.length > 0) {
				try {
					new GLib.Regex(pattern);
				} catch (GLib.RegexError e) {
					var alert = new Adw.AlertDialog(
						"Success criteria is not a valid regular expression.",
						null
					) {
						default_response = "ok",
						close_response = "ok"
					};
					alert.add_response("ok", "OK");
					alert.present(this.sender);
					return;
				}
			}
			if (!this.root_check.active) {
				this.write(testing, pattern);
				return;
			}
			this.authorizing = true;
			this.authorize.begin(testing, pattern, (obj, res) => {
				this.authorizing = false;
				this.authorize.end(res);
			});
		}

		/**
		 * ``pkexec /usr/bin/true`` before a root script is stored.
		 *
		 * PolicyKit may reuse a recent grant and show no dialog.
		 * Any other result leaves the stored row unchanged.
		 *
		 * @param testing true from Run/Test
		 * @param pattern stripped success criteria
		 */
		private async void authorize(bool testing, string pattern)
		{
			try {
				var proc = new GLib.Subprocess.newv(
					{ "pkexec", "/usr/bin/true" },
					GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE
				);
				yield proc.wait_check_async();
			} catch (GLib.Error e) {
				GLib.debug("root auth failed: %s", e.message);
				var alert = new Adw.AlertDialog(
					"Run as root was not authorized. The command was not saved.",
					null
				) {
					default_response = "ok",
					close_response = "ok"
				};
				alert.add_response("ok", "OK");
				alert.present(this.sender);
				return;
			}
			this.write(testing, pattern);
		}

		/**
		 * Write the form onto {@link row} and store it.
		 *
		 * @param testing true from Run/Test
		 * @param pattern stripped success criteria
		 */
		private void write(bool testing, string pattern)
		{
			this.row.path = this.path_entry.text.strip();
			this.row.body = this.body.buffer.text;
			this.row.success_regex = pattern;
			this.row.run_as_root = this.root_check.active;
			this.sender.store.save(this.row);
			this.delete_btn.visible = this.row.id > 0;
			if (!testing) {
				this.sender.show_page(RooTerm.Dialog.Script.Page.EDIT);
				return;
			}
			if (this.sender.hosts.task.id < 1) {
				this.sender.hosts.task = new RooTerm.SQT.Task() {
					is_script = true,
					script_id = this.row.id,
					is_draft = true
				};
				this.sender.hosts.tasks.save(this.sender.hosts.task);
			}
			this.sender.hosts.script = this.row;
			this.sender.run.stopped = false;
			this.sender.show_page(RooTerm.Dialog.Script.Page.PLAN);
		}

		/**
		 * Show ''row''. An id of 0 is a new command.
		 *
		 * Clears the host ticks. The next Run/Test starts a new visit.
		 *
		 * @param row script to edit
		 */
		public void load(RooTerm.SQT.Script row)
		{
			this.row = row;
			this.path_entry.text = row.path;
			this.body.buffer.text = row.body;
			this.success_entry.text = row.success_regex;
			this.root_check.active = row.run_as_root;
			this.delete_btn.visible = row.id > 0;
			this.sender.hosts.picks.clear();
			this.sender.hosts.picks_changed();
			this.sender.hosts.task = new RooTerm.SQT.Task();
			this.sender.hosts.refresh_select();
			this.sender.run.wave++;
			this.sender.run.stopped = true;
			for (var i = 0; i < this.sender.run.jobs.size; i++) {
				this.sender.run.jobs.get(i).halt = true;
				this.sender.run.jobs.get(i).released = true;
			}
		}
	}
}
