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
	 * Create or edit one {@link RooTerm.SQT.Script}.
	 *
	 * The form is the nickname, the commands to run, and an optional
	 * success criteria line under the command.
	 * Save asks {@link RooTerm.Store.Script.save}. Test saves first,
	 * then opens planning on this form so the command can be tried.
	 * Delete asks for confirmation, then {@link RooTerm.Store.Script.remove}.
	 * Shell role ``script-form``: same Register / Show / Hide as Preferences.
	 * Cancel hides this window. There is no titlebar close button.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var dialog = new RooTerm.Dialog.Script(store, sender);
	 * dialog.open(new RooTerm.SQT.Script());
	 * }}}
	 */
	public class Script : Adw.Window
	{
		public RooTerm.Store.Script store;
		private weak RooTerm.MainWindow main;
		private RooTerm.SQT.Script row;
		private Gtk.Entry path_entry;
		private Gtk.TextView body;
		private Gtk.Entry success_entry;
		private Gtk.Button delete_btn;

		/**
		 * @param store library this form writes
		 * @param parent Script sender window
		 * @param main Main window (Shell register / show)
		 */
		public Script(
			RooTerm.Store.Script store,
			Gtk.Window parent,
			RooTerm.MainWindow main
		)
		{
			Object(
				application: main.application,
				title: "Add Command",
				transient_for: parent,
				modal: true,
				deletable: false,
				hide_on_close: true,
				default_width: 640,
				default_height: 560
			);
			this.store = store;
			this.main = main;
			this.add_css_class("floating-dialog");
			this.map.connect(() => {
				GLib.Idle.add(() => {
					this.main.shell.register(this, "script-form");
					return false;
				});
			});
			this.close_request.connect(() => {
				this.main.dbus.call_shell_async("hide", new GLib.Variant("(s)", "script-form"));
				return false;
			});
			this.row = new RooTerm.SQT.Script();
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
			var success_hint = new Gtk.Label("Use this to validate completion or success.") {
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
				margin_top = 6,
				margin_bottom = 16
			};
			success_row.append(this.success_entry);
			var cancel = new Gtk.Button.with_label("Cancel");
			cancel.clicked.connect(() => {
				this.close();
			});
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
					this.store.remove(this.row);
					this.close();
				});
				alert.present(this);
			});
			var save = new Gtk.Button.with_label("Save") {
				css_classes = { "suggested-action" }
			};
			save.clicked.connect(() => {
				this.on_save_click(false);
			});
			var test = new Gtk.Button.with_label("Test");
			test.clicked.connect(() => {
				this.on_save_click(true);
			});
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			header.pack_start(cancel);
			header.pack_start(this.delete_btn);
			header.pack_end(save);
			header.pack_end(test);
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			box.append(path_row);
			box.append(command_title);
			box.append(guidance);
			box.append(scrolled);
			box.append(success_title);
			box.append(success_hint);
			box.append(success_row);
			var toolbar = new Adw.ToolbarView() {
				content = box
			};
			toolbar.add_top_bar(header);
			this.content = toolbar;
		}

		/**
		 * Save click. ''testing'' opens planning instead of closing.
		 *
		 * An empty nickname or a bad regex does not save.
		 *
		 * @param testing true from the Test button
		 */
		private void on_save_click(bool testing)
		{
			if (this.path_entry.text.strip().length == 0) {
				return;
			}
			var pattern = this.success_entry.text.strip();
			if (pattern.length == 0) {
				this.row.path = this.path_entry.text.strip();
				this.row.body = this.body.buffer.text;
				this.row.success_regex = "";
				this.store.save(this.row);
				if (!testing) {
					this.close();
					return;
				}
				this.title = "Edit Command";
				this.delete_btn.visible = true;
				var plan = new RooTerm.Dialog.Plan(this.main, this);
				plan.open(this.row, this.main.tree);
				return;
			}
			try {
				new GLib.Regex(pattern);
			} catch (GLib.RegexError e) {
				var alert = new Adw.AlertDialog("Success criteria is not a valid regular expression.", null) {
					default_response = "ok",
					close_response = "ok"
				};
				alert.add_response("ok", "OK");
				alert.present(this);
				return;
			}
			this.row.path = this.path_entry.text.strip();
			this.row.body = this.body.buffer.text;
			this.row.success_regex = pattern;
			this.store.save(this.row);
			if (!testing) {
				this.close();
				return;
			}
			this.title = "Edit Command";
			this.delete_btn.visible = true;
			var plan = new RooTerm.Dialog.Plan(this.main, this);
			plan.open(this.row, this.main.tree);
		}

		/**
		 * Show ''row''. An id of 0 is a new command.
		 *
		 * @param row script to edit
		 */
		public void open(RooTerm.SQT.Script row)
		{
			this.row = row;
			this.title = row.id > 0 ? "Edit Command" : "Add Command";
			this.path_entry.text = row.path;
			this.body.buffer.text = row.body;
			this.success_entry.text = row.success_regex;
			this.delete_btn.visible = row.id > 0;
			this.present();
			GLib.Timeout.add(50, () => {
				this.main.dbus.call_shell_async("show", new GLib.Variant("(s)", "script-form"));
				return false;
			});
		}
	}
}
