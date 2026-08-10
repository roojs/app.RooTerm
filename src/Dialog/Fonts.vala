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
	 * Monospace font catalogue for prefs: {@link GLib.ListModel} of {@link Font}
	 * plus {@link by_name} (no scan-to-find).
	 *
	 * Bind combos to this object. Rows use {@link GLib.ListStore.insert_sorted}
	 * (System first, then name). Prefs-only under {@link RooTerm.Dialog}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var fonts = new Dialog.Fonts();
	 * fonts.load();
	 * combo.model = fonts;
	 * uint pos;
	 * fonts.find(fonts.by_name.get("Ubuntu Sans Mono"), out pos);
	 * }}}
	 */
	public class Fonts : GLib.Object, GLib.ListModel
	{
		/**
		 * Family name → font (System not keyed; empty config uses index 0).
		 */
		public Gee.HashMap<string, Font> by_name {
			get;
			set;
			default = new Gee.HashMap<string, Font>();
		}
		private GLib.ListStore store = new GLib.ListStore(typeof(Font));

		construct
		{
			this.store.items_changed.connect((position, removed, added) => {
				this.items_changed(position, removed, added);
			});
		}

		/**
		 * {@inheritDoc}
		 */
		public GLib.Type get_item_type()
		{
			return this.store.get_item_type();
		}

		/**
		 * {@inheritDoc}
		 */
		public uint get_n_items()
		{
			return this.store.get_n_items();
		}

		/**
		 * {@inheritDoc}
		 */
		public GLib.Object? get_item(uint position)
		{
			return this.store.get_item(position);
		}

		/**
		 * {@link GLib.ListStore.find} on the backing store.
		 *
		 * @param item Row to locate
		 * @param position Out index when found
		 * @return Whether ``item`` is in the store
		 */
		public bool find(GLib.Object item, out uint position)
		{
			return this.store.find(item, out position);
		}

		/**
		 * System monospace family from
		 * ``org.gnome.desktop.interface`` ``monospace-font-name``.
		 *
		 * @return Family name (fallback ``Monospace``)
		 */
		public static string system()
		{
			var face = "Monospace";
			var schema = GLib.SettingsSchemaSource.get_default().lookup(
				"org.gnome.desktop.interface", true
			);
			if (schema == null) {
				return face;
			}
			var sys = Pango.FontDescription.from_string(
				new GLib.Settings.full(schema, null, null).get_string(
					"monospace-font-name"
				)
			);
			if (sys.get_family() == null || sys.get_family().length == 0) {
				return face;
			}
			return sys.get_family();
		}

		/**
		 * System monospace size in points from
		 * ``org.gnome.desktop.interface`` ``monospace-font-name``.
		 *
		 * @return Size in points (fallback ``9``)
		 */
		public static int system_size()
		{
			var points = 9;
			var schema = GLib.SettingsSchemaSource.get_default().lookup(
				"org.gnome.desktop.interface", true
			);
			if (schema == null) {
				return points;
			}
			var sys = Pango.FontDescription.from_string(
				new GLib.Settings.full(schema, null, null).get_string(
					"monospace-font-name"
				)
			);
			if (sys.get_size() <= 0) {
				return points;
			}
			return sys.get_size() / Pango.SCALE;
		}

		/**
		 * Load monospace families from the default Pango font map.
		 * Safe to call once; later calls are ignored when already loaded.
		 */
		public void load()
		{
			if (this.store.n_items > 0) {
				return;
			}
			GLib.CompareDataFunc<GLib.Object> cmp = (a, b) => {
				var left = (Font) a;
				var right = (Font) b;
				if (left.name.length == 0) {
					return -1;
				}
				if (right.name.length == 0) {
					return 1;
				}
				return left.name.collate(right.name);
			};
			this.store.insert_sorted(new Font(""), cmp);
			Pango.FontFamily[] families;
			((Pango.FontMap) Pango.CairoFontMap.get_default()).list_families(out families);
			foreach (var fam in families) {
				if (!fam.is_monospace()) {
					continue;
				}
				var face = new Font(fam.get_name());
				this.store.insert_sorted(face, cmp);
				this.by_name.set(face.name, face);
			}
		}
	}
}
