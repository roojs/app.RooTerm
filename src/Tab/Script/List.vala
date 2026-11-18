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
	 * Command list for {@link RooTerm.Dialog.Script}.
	 *
	 * Search, the nickname column, and the command column.
	 * Double-click and the play button both open
	 * {@link RooTerm.Tab.Script.Edit}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var list = new RooTerm.Tab.Script.List(sender);
	 * }}}
	 */
	public class List : Gtk.Box
	{
		private weak RooTerm.Dialog.Script sender;
		private RooTerm.Filter.Script filter;

		/**
		 * @param sender script sender window
		 */
		public List(RooTerm.Dialog.Script sender)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				hexpand: true,
				vexpand: true
			);
			this.sender = sender;
			this.filter = new RooTerm.Filter.Script();
			var listed = new Gtk.FilterListModel(sender.store, this.filter) {
				incremental = false
			};
			var names = new Gtk.SignalListItemFactory();
			names.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END
				};
			});
			names.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (RooTerm.SQT.Script) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.path;
			});
			var commands = new Gtk.SignalListItemFactory();
			commands.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var label = new Gtk.Label("") {
					xalign = 0,
					yalign = 0,
					hexpand = true,
					wrap = true,
					wrap_mode = Pango.WrapMode.CHAR
				};
				label.add_css_class("monospace");
				label.add_css_class("caption");
				item.child = label;
			});
			commands.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (RooTerm.SQT.Script) item.item;
				var label = (Gtk.Label) item.child;
				var lines = row.body.split("\n");
				var text = lines.length > 0 ? lines[0] : "";
				if (lines.length > 1) {
					text += "\n" + lines[1];
				}
				if (lines.length > 2) {
					text += "\n...";
				}
				label.label = text;
			});
			var selection = new Gtk.SingleSelection(listed) {
				autoselect = false,
				can_unselect = true
			};
			var grid = new Gtk.ColumnView(selection) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			grid.append_column(new Gtk.ColumnViewColumn("Command Nickname", names) {
				resizable = true,
				fixed_width = 180
			});
			grid.append_column(new Gtk.ColumnViewColumn("Command", commands) {
				expand = true,
				resizable = true
			});
			var runs = new Gtk.SignalListItemFactory();
			runs.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var button = new Gtk.Button.from_icon_name("media-playback-start-symbolic") {
					tooltip_text = "Execute",
					halign = Gtk.Align.CENTER,
					valign = Gtk.Align.CENTER
				};
				button.add_css_class("flat");
				button.clicked.connect(() => {
					var row = button.get_data<RooTerm.SQT.Script>("script-row");
					if (row == null) {
						return;
					}
					this.sender.edit.load(row);
					this.sender.show_page(RooTerm.Dialog.Script.Page.EDIT);
				});
				item.child = button;
			});
			runs.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (RooTerm.SQT.Script) item.item;
				var button = (Gtk.Button) item.child;
				button.set_data("script-row", row);
			});
			grid.append_column(new Gtk.ColumnViewColumn("", runs) {
				fixed_width = 48
			});
			var empty = new Adw.StatusPage() {
				title = "No scripts",
				description = "Add command creates a script.",
				icon_name = "text-x-script-symbolic",
				vexpand = true
			};
			var body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			body.add_named(new Gtk.ScrolledWindow() {
				child = grid,
				hexpand = true,
				vexpand = true
			}, "list");
			body.add_named(empty, "empty");
			body.visible_child_name = "empty";
			var search = new Gtk.SearchEntry() {
				placeholder_text = "Search commands",
				hexpand = true
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var search_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				margin_start = 16,
				margin_end = 16,
				margin_top = 12,
				margin_bottom = 12
			};
			search_row.append(search);
			this.append(search_row);
			this.append(body);
			this.sender.store.notify["empty"].connect(() => {
				if (this.sender.store.empty) {
					body.visible_child_name = "empty";
					return;
				}
				body.visible_child_name = "list";
			});
			grid.activate.connect((position) => {
				var row = selection.get_item(position) as RooTerm.SQT.Script;
				if (row == null) {
					return;
				}
				this.sender.edit.load(row);
				this.sender.show_page(RooTerm.Dialog.Script.Page.EDIT);
			});
			this.sender.store.load();
			if (this.sender.store.empty) {
				body.visible_child_name = "empty";
				return;
			}
			body.visible_child_name = "list";
		}
	}
}
