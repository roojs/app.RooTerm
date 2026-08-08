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
	 * Foreground theme selector: ← | {@link Adw.ComboRow} | → on a
	 * {@link Gtk.FilterListModel} over {@link RooTerm.Themes} (category filter).
	 *
	 * Bound to ``theme-name``. {@link category_row} updates the filter search
	 * (same idea as {@link Host.SearchPulldown}).
	 *
	 * == Example ==
	 *
	 * {{{
	 * var bg = new Dialog.RowCombo(config, "theme-category", { "black", "dark" });
	 * var theme = new Dialog.RowThemeSelect(config, "theme-name", bg);
	 * }}}
	 */
	public class RowThemeSelect : Row
	{
		public Adw.ComboRow combo;
		/**
		 * Background colour row that sets {@link category_filter} search.
		 */
		public RowCombo category_row;
		/**
		 * Exact match on {@link Theme.category}.
		 */
		public Gtk.StringFilter category_filter;
		/**
		 * Filtered view of {@link Config.themes} bound to {@link combo}.
		 */
		public Gtk.FilterListModel filtered;

		/**
		 * @param config Chrome settings
		 * @param key Hyphenated string property (``theme-name``)
		 * @param category_row Background colour {@link RowCombo}
		 */
		public RowThemeSelect(Config config, string key, RowCombo category_row)
		{
			base(config, key);
			this.category_row = category_row;
			this.config.themes.load();
			this.category_filter = new Gtk.StringFilter(
				new Gtk.PropertyExpression(typeof(Theme), null, "category")
			) {
				match_mode = Gtk.StringFilterMatchMode.EXACT,
				search = "black"
			};
			this.filtered = new Gtk.FilterListModel(
				this.config.themes, this.category_filter
			);
			this.combo = new Adw.ComboRow() {
				title = this.pspec.get_nick(),
				subtitle = this.pspec.get_blurb(),
				model = this.filtered,
				expression = new Gtk.PropertyExpression(typeof(Theme), null, "name")
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
				if (this.loading
						|| this.combo.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				this.send(((Theme) this.combo.selected_item).name);
			});
			this.category_row.combo.notify["selected"].connect(() => {
				if (this.loading
						|| this.category_row.loading
						|| this.category_row.combo.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				var item = (Gtk.StringObject) this.category_row.combo.selected_item;
				this.loading = true;
				this.category_filter.search = item.string;
				this.combo.selected = Gtk.INVALID_LIST_POSITION;
				this.loading = false;
				// After loading — so preview / send see the new first theme.
				this.combo.selected = 0;
			});
		}

		public override void fill()
		{
			this.loading = true;
			var value = Value(typeof(string));
			this.read(ref value);
			var name = value.get_string();
			var cat = Value(typeof(string));
			((GLib.Object) this.config).get_property("theme-category", ref cat);
			var cat_str = cat.get_string();
			this.category_filter.search = cat_str;
			var map_key = cat_str + "\n" + name;
			if (name == "" || !this.config.themes.by_key.has_key(map_key)) {
				this.combo.selected = 0;
				this.loading = false;
				return;
			}
			uint pos;
			this.config.themes.by_category.get(cat_str).find(
				this.config.themes.by_key.get(map_key), out pos
			);
			this.combo.selected = pos;
			this.loading = false;
		}
	}
}
