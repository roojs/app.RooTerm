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
	 * One VTE colour scheme from ``resources/themes/theme-*.ini``.
	 *
	 * Stock colours are derived from Guake ``palettes.py`` (attributed there).
	 * Loaded into {@link Themes}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * config.themes.load();
	 * var theme = config.themes.by_key.get("dark\nSolarized");
	 * }}}
	 */
	public class Theme : GLib.Object
	{
		/**
		 * Display name (unique within {@link category}).
		 */
		public string name { get; set; default = ""; }
		/**
		 * Background bucket: ``black``, ``dark-grey``, ``dark``, ``off-white``, ``white``.
		 */
		public string category { get; set; default = ""; }
		/**
		 * Foreground ``#RRGGBB``.
		 */
		public string foreground { get; set; default = ""; }
		/**
		 * Background ``#RRGGBB``.
		 */
		public string background { get; set; default = ""; }
		/**
		 * Sixteen palette colours as ``#RRGGBB``, semicolon-separated.
		 */
		public string palette { get; set; default = ""; }

		/**
		 * Read ``foreground`` / ``background`` / ``palette`` from ``key`` group ``name``.
		 *
		 * @param name Theme / keyfile group name
		 * @param category Background bucket slug
		 * @param key Open keyfile for that category
		 */
		public Theme(string name, string category, GLib.KeyFile key)
		{
			Object();
			this.name = name;
			this.category = category;
			this.foreground = key.get_string(name, "foreground");
			this.background = key.get_string(name, "background");
			this.palette = key.get_string(name, "palette");
		}
	}
}
