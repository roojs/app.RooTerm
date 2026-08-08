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
	 * Stock theme catalogue: {@link GLib.ListModel} over an ArrayList of
	 * {@link Theme}, plus lookup maps (no scan-to-find).
	 *
	 * Same pattern as {@link Host.TreeNodes}. {@link by_key} is
	 * ``category + "\\n" + name``; {@link by_category} is a ListStore per
	 * background bucket for prefs filtering.
	 *
	 * Owned by {@link RooTerm.Config.themes}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * config.themes.load();
	 * var pick = config.themes.by_key.get("dark\nSolarized");
	 * var dark = config.themes.by_category.get("dark");
	 * }}}
	 */
	public class Themes : GLib.Object, GLib.ListModel
	{
		/**
		 * All loaded themes (ArrayList backing this ListModel).
		 */
		public Gee.ArrayList<Theme> items {
			get;
			set;
			default = new Gee.ArrayList<Theme>();
		}
		/**
		 * ``category + "\\n" + name`` → theme.
		 */
		public Gee.HashMap<string, Theme> by_key {
			get;
			set;
			default = new Gee.HashMap<string, Theme>();
		}
		/**
		 * Category slug → themes in that bucket (for filtered prefs lists).
		 */
		public Gee.HashMap<string, GLib.ListStore> by_category {
			get;
			set;
			default = new Gee.HashMap<string, GLib.ListStore>();
		}

		/**
		 * {@inheritDoc}
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Theme);
		}

		/**
		 * {@inheritDoc}
		 */
		public uint get_n_items()
		{
			return this.items.size;
		}

		/**
		 * {@inheritDoc}
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Load ``/themes/theme-*.ini`` from gresource into this catalogue.
		 * Safe to call once; later calls are ignored when already loaded.
		 */
		public void load()
		{
			if (this.items.size > 0) {
				return;
			}
			string[] files = {
				"black",
				"dark-grey",
				"dark",
				"off-white",
				"white"
			};
			foreach (var cat in files) {
				var bytes = GLib.resources_lookup_data(
					"/themes/theme-%s.ini".printf(cat),
					GLib.ResourceLookupFlags.NONE
				);
				var key = new GLib.KeyFile();
				key.load_from_bytes(bytes, GLib.KeyFileFlags.NONE);
				var cat_store = new GLib.ListStore(typeof(Theme));
				this.by_category.set(cat, cat_store);
				foreach (var group in key.get_groups()) {
					var theme = new Theme(group, cat, key);
					this.items.add(theme);
					cat_store.append(theme);
					this.by_key.set(cat + "\n" + group, theme);
				}
			}
			this.items_changed(0, 0, this.items.size);
		}
	}
}
