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
	 * {@link Gtk.Switch} suffix on an {@link Adw.ActionRow} for a Config bool.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var remember = new Dialog.RowSwitch(config, "remember-workspace-tab");
	 * group.add(remember.row);
	 * remember.fill();
	 * }}}
	 */
	public class RowSwitch : Row
	{
		public Gtk.Switch control;

		/**
		 * @param config Chrome settings
		 * @param key Hyphenated bool property
		 */
		public RowSwitch(Config config, string key)
		{
			base(config, key);
			this.control = new Gtk.Switch() {
				valign = Gtk.Align.CENTER
			};
			this.control.notify["active"].connect(() => {
				this.send(this.control.active ? "true" : "false");
			});
			((Adw.ActionRow) this.row).add_suffix(this.control);
			((Adw.ActionRow) this.row).set_activatable_widget(this.control);
		}

		public override void fill()
		{
			this.loading = true;
			var value = Value(typeof(bool));
			this.read(ref value);
			this.control.active = value.get_boolean();
			this.loading = false;
		}
	}
}
