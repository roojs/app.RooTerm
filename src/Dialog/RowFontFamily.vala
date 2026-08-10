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
	 * Monospace font family selector: ← | {@link Adw.ComboRow} | →.
	 *
	 * Model is {@link Fonts} (System first via insert_sorted). Cells use
	 * {@link Font.label} / {@link Font.attributes}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var family = new Dialog.RowFontFamily(config, "font-family");
	 * group.add(family.row);
	 * family.fill();
	 * }}}
	 */
	public class RowFontFamily : Row
	{
		public Adw.ComboRow combo;
		public Fonts fonts;

		/**
		 * @param config Chrome settings
		 * @param key Hyphenated string property (``font-family``)
		 */
		public RowFontFamily(Config config, string key)
		{
			base(config, key);
			this.fonts = new Fonts();
			this.fonts.load();
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((obj) => {
				var label = new Gtk.Label("") {
					xalign = 0f,
					ellipsize = Pango.EllipsizeMode.END,
					hexpand = true
				};
				((Gtk.ListItem) obj).child = label;
			});
			factory.bind.connect((obj) => {
				var list_item = (Gtk.ListItem) obj;
				var label = (Gtk.Label) list_item.child;
				var face = (Font) list_item.item;
				label.label = face.label();
				label.attributes = face.attributes();
			});
			this.combo = new Adw.ComboRow() {
				title = this.pspec.get_nick(),
				model = this.fonts,
				factory = factory,
				list_factory = factory
			};
			this.row = this.combo;
			var prev = new Gtk.Button.from_icon_name("go-previous-symbolic") {
				valign = Gtk.Align.CENTER,
				css_classes = { "flat" }
			};
			var next = new Gtk.Button.from_icon_name("go-next-symbolic") {
				valign = Gtk.Align.CENTER,
				css_classes = { "flat" }
			};
			this.combo.add_prefix(prev);
			this.combo.add_suffix(next);
			prev.clicked.connect(() => {
				if (this.loading
						|| this.combo.selected == Gtk.INVALID_LIST_POSITION
						|| this.combo.selected == 0) {
					return;
				}
				this.combo.selected = this.combo.selected - 1;
			});
			next.clicked.connect(() => {
				if (this.loading
						|| this.combo.selected == Gtk.INVALID_LIST_POSITION
						|| this.combo.selected + 1 >= this.combo.model.get_n_items()) {
					return;
				}
				this.combo.selected = this.combo.selected + 1;
			});
			this.combo.notify["selected"].connect(() => {
				if (this.combo.selected == Gtk.INVALID_LIST_POSITION) {
					this.combo.subtitle = "";
					return;
				}
				var face = (Font) this.combo.selected_item;
				if (face.name.length == 0) {
					this.combo.subtitle = Fonts.system();
				} else {
					this.combo.subtitle = "";
				}
				if (this.loading) {
					return;
				}
				this.send(face.name);
			});
		}

		public override void fill()
		{
			this.loading = true;
			var value = Value(typeof(string));
			this.read(ref value);
			var text = value.get_string();
			if (text == "" || !this.fonts.by_name.has_key(text)) {
				this.combo.selected = 0;
			} else {
				uint pos;
				this.fonts.find(this.fonts.by_name.get(text), out pos);
				this.combo.selected = pos;
			}
			var face = (Font) this.combo.selected_item;
			if (face.name.length == 0) {
				this.combo.subtitle = Fonts.system();
			} else {
				this.combo.subtitle = "";
			}
			this.loading = false;
		}
	}
}
