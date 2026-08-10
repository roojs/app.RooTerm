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
	 * One monospace font family row for {@link Fonts} (prefs combo).
	 *
	 * Empty {@link name} is the **System** sentinel (stored config value).
	 *
	 * == Example ==
	 *
	 * {{{
	 * var face = new Dialog.Font("Ubuntu Sans Mono");
	 * label.label = face.label();
	 * label.attributes = face.attributes();
	 * }}}
	 */
	public class Font : GLib.Object
	{
		/**
		 * Pango family name; empty = system monospace.
		 */
		public string name { get; set; default = ""; }

		/**
		 * @param name Family name, or empty for System
		 */
		public Font(string name = "")
		{
			Object(name: name);
		}

		/**
		 * Combo display text (**System** when {@link name} is empty).
		 *
		 * @return Label for the prefs cell
		 */
		public string label()
		{
			if (this.name.length == 0) {
				return "System";
			}
			return this.name;
		}

		/**
		 * Pango attrs so the cell is drawn in this family (system monospace
		 * when {@link name} is empty).
		 *
		 * @return Attribute list for the prefs cell
		 */
		public Pango.AttrList attributes()
		{
			var face = this.name;
			if (face.length == 0) {
				face = Fonts.system();
			}
			var desc = new Pango.FontDescription();
			desc.set_family(face);
			desc.set_size(Fonts.system_size() * Pango.SCALE);
			var attrs = new Pango.AttrList();
			attrs.insert(new Pango.AttrFontDesc(desc));
			return attrs;
		}
	}
}
