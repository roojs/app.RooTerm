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
	 * Preferences row bound to one {@link RooTerm.Config} GObject property.
	 *
	 * Composes an {@link Adw.PreferencesRow} (does not subclass
	 * {@link Adw.ActionRow}). Property names use hyphens (``key-toggle``), matching
	 * {@link GLib.ObjectClass.find_property}. User edits call {@link send}, which
	 * fires ``config_update`` on ``org.roojs.RooTerm.DBus``. If main is not on
	 * the bus, applies the value on {@link config} and {@link Config.save}.
	 * Not wired into {@link Preferences} yet.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var opacity = new Dialog.RowScale(config, "opacity", 10, 100, 1);
	 * group.add(opacity.row);
	 * opacity.fill();
	 * }}}
	 */
	public abstract class Row : GLib.Object
	{
		/**
		 * Widget to add to an {@link Adw.PreferencesGroup}.
		 */
		public Adw.PreferencesRow row;

		/**
		 * Chrome config this row edits (read for {@link fill} only).
		 */
		public Config config;

		/**
		 * Property this row binds (name is hyphenated).
		 */
		public ParamSpec pspec;

		/**
		 * True while {@link fill} is updating widgets (ignore control signals).
		 */
		public bool loading = false;

		/**
		 * Hyphenated GObject property name (e.g. ``key-toggle``).
		 */
		public string key {
			get {
				return this.pspec.get_name();
			}
		}

		/**
		 * Resolve ``key`` on ``config`` and build {@link row} title/subtitle from nick/blurb.
		 *
		 * @param config Chrome settings object
		 * @param key Hyphenated property name (``opacity``, ``key-toggle``, …)
		 */
		protected Row(Config config, string key)
		{
			this.config = config;
			var pspec = config.find_property(key);
			if (pspec == null) {
				GLib.error("unknown config property: %s", key);
			}
			this.pspec = pspec;
			this.row = new Adw.ActionRow() {
				title = this.pspec.get_nick(),
				subtitle = this.pspec.get_blurb()
			};
		}

		/**
		 * Load the widget from {@link config} (sets {@link loading} around the update).
		 */
		public abstract void fill();

		/**
		 * Call main ``config_update`` with this row's {@link key} unless {@link loading}.
		 * Async — ``call_sync`` to our own bus name deadlocks (prefs still in-process).
		 * On failure (main not running), set the property locally and save.
		 *
		 * @param value String form of the control value
		 */
		public void send(string value)
		{
			if (this.loading) {
				return;
			}
			try {
				var bus = GLib.Bus.get_sync(GLib.BusType.SESSION, null);
				bus.call.begin("org.roojs.RooTerm.DBus",
					"/org/roojs/RooTerm/DBus", "org.roojs.RooTerm.DBus",
					"config_update", new GLib.Variant("(ss)", this.key, value),
					null, GLib.DBusCallFlags.NONE, -1, null,
					(s, res) => {
						try {
							bus.call.end(res);
						} catch (GLib.Error e) {
							GLib.debug("config_update %s: %s — save locally",
								this.key, e.message);
							var parsed = Value(this.pspec.value_type);
							switch (this.pspec.value_type) {
								case GLib.Type.INT:
									parsed.set_int(int.parse(value));
									break;

								case GLib.Type.STRING:
									parsed.set_string(value);
									break;

								case GLib.Type.BOOLEAN:
									parsed.set_boolean(value == "true");
									break;

								default:
									GLib.warning(
										"unsupported config type for %s", this.key
									);
									return;
							}
							((GLib.Object) this.config).set_property(
								this.key, parsed
							);
							this.config.save();
						}
					}
				);
			} catch (GLib.Error e) {
				GLib.debug("config_update %s: %s — save locally", this.key, e.message);
				var parsed = Value(this.pspec.value_type);
				switch (this.pspec.value_type) {
					case GLib.Type.INT:
						parsed.set_int(int.parse(value));
						break;

					case GLib.Type.STRING:
						parsed.set_string(value);
						break;

					case GLib.Type.BOOLEAN:
						parsed.set_boolean(value == "true");
						break;

					default:
						GLib.warning("unsupported config type for %s", this.key);
						return;
				}
				((GLib.Object) this.config).set_property(this.key, parsed);
				this.config.save();
			}
		}

		/**
		 * Read the bound property into ``value`` (caller sets the Value type).
		 *
		 * @param value Out-style Value to fill via {@link GLib.Object.get_property}
		 */
		protected void read(ref Value value)
		{
			((GLib.Object) this.config).get_property(this.key, ref value);
		}
	}
}
