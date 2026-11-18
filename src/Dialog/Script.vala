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
	 * Script sender.
	 *
	 * One window. The stack is the command list, the edit form, the
	 * host picker, and the terminals. {@link show_page} is the only
	 * way to change page. Shell role ``script``.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var sender = new RooTerm.Dialog.Script(window);
	 * sender.present();
	 * }}}
	 */
	public class Script : Adw.ApplicationWindow
	{
		/**
		 * Pages of this window. Names in the code only.
		 */
		public enum Page {
			LIST,
			EDIT,
			PLAN,
			RUN
		}

		/**
		 * Library this window lists and edits.
		 */
		public RooTerm.Store.Script store;
		/**
		 * Main window, for the database, the host tree, and Shell.
		 */
		public weak RooTerm.MainWindow main;
		/**
		 * Command list page.
		 */
		public RooTerm.Tab.Script.List list;
		/**
		 * Edit command page.
		 */
		public RooTerm.Tab.Script.Edit edit;
		/**
		 * Host picker page.
		 */
		public RooTerm.Tab.Script.Hosts hosts;
		/**
		 * Terminals page.
		 */
		public RooTerm.Tab.Script.Run run;
		private Gtk.Stack stack;
		private Adw.HeaderBar header;
		private Gtk.Button close_btn;
		private Gtk.Button add_btn;
		private Gtk.Button back_btn;
		private Page page = Page.LIST;

		/**
		 * @param window main window, for the open database
		 */
		public Script(RooTerm.MainWindow window)
		{
			Object(
				application: window.application,
				title: "Script sender",
				deletable: false,
				hide_on_close: false,
				default_width: 1008,
				default_height: 728
			);
			this.main = window;
			this.add_css_class("floating-dialog");
			this.store = new RooTerm.Store.Script(window.tree.db);
			this.stack = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.run = new RooTerm.Tab.Script.Run(this);
			this.hosts = new RooTerm.Tab.Script.Hosts(this);
			this.edit = new RooTerm.Tab.Script.Edit(this);
			this.list = new RooTerm.Tab.Script.List(this);
			this.stack.add_named(this.list, Page.LIST.to_string());
			this.stack.add_named(this.edit, Page.EDIT.to_string());
			this.stack.add_named(this.hosts, Page.PLAN.to_string());
			this.stack.add_named(this.run, Page.RUN.to_string());
			this.close_btn = new Gtk.Button.with_label("Close");
			this.close_btn.clicked.connect(() => {
				this.close();
			});
			this.add_btn = new Gtk.Button.with_label("Add command") {
				css_classes = { "suggested-action" }
			};
			this.add_btn.clicked.connect(() => {
				this.edit.load(new RooTerm.SQT.Script());
				this.show_page(Page.EDIT);
			});
			this.back_btn = new Gtk.Button.with_label("Back");
			this.back_btn.clicked.connect(() => {
				switch (this.page) {
					case Page.EDIT:
						this.show_page(Page.LIST);
						break;

					case Page.PLAN:
						this.show_page(Page.EDIT);
						break;

					case Page.RUN:
						this.show_page(Page.EDIT);
						break;

					default:
						break;
				}
			});
			this.header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			var toolbar = new Adw.ToolbarView() {
				content = this.stack
			};
			toolbar.add_top_bar(this.header);
			this.content = toolbar;
			this.map.connect(() => {
				GLib.Idle.add(() => {
					this.main.shell.register(this, "script");
					return false;
				});
			});
			this.close_request.connect(() => {
				if (this.page == Page.RUN && !this.run.done) {
					return true;
				}
				for (var i = 0; i < this.run.jobs.size; i++) {
					var pid = this.run.jobs.get(i).terminal.child_pid;
					if (pid < 1) {
						continue;
					}
					Posix.kill(pid, Posix.Signal.TERM);
				}
				this.main.dbus.call_shell_async("hide", new GLib.Variant("(s)", "script"));
				return true;
			});
			this.show_page(Page.LIST);
		}

		/**
		 * Show one sender page and repack the header for it.
		 *
		 * @param page list, edit, plan, or run
		 */
		public void show_page(Page page)
		{
			this.page = page;
			this.stack.visible_child_name = page.to_string();
			if (this.close_btn.parent != null) {
				this.header.remove(this.close_btn);
			}
			if (this.add_btn.parent != null) {
				this.header.remove(this.add_btn);
			}
			if (this.back_btn.parent != null) {
				this.header.remove(this.back_btn);
			}
			if (this.edit.run_btn.parent != null) {
				this.header.remove(this.edit.run_btn);
			}
			if (this.run.start_btn.parent != null) {
				this.header.remove(this.run.start_btn);
			}
			if (this.run.cancel_btn.parent != null) {
				this.header.remove(this.run.cancel_btn);
			}
			switch (page) {
				case Page.LIST:
					this.title = "Script sender";
					this.header.pack_start(this.close_btn);
					this.header.pack_end(this.add_btn);
					break;

				case Page.EDIT:
					this.title = "Add Command";
					if (this.edit.row.id > 0) {
						this.title = "Edit Command";
					}
					this.header.pack_start(this.back_btn);
					this.header.pack_end(this.edit.run_btn);
					break;

				case Page.PLAN:
					this.title = "Hosts to execute commands";
					if (this.edit.row.path.strip() != "") {
						this.title = "Hosts to execute '" + this.edit.row.path.strip() + "'";
					}
					this.header.pack_start(this.back_btn);
					this.header.pack_end(this.run.start_btn);
					this.hosts.refresh_select();
					this.hosts.picks_changed();
					break;

				case Page.RUN:
					if (this.run.done) {
						this.header.pack_start(this.back_btn);
						break;
					}
					this.header.pack_end(this.run.cancel_btn);
					break;

				default:
					break;
			}
		}
	}
}
