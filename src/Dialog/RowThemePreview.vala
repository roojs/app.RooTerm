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
	 * Theme preview: live VTE sample from ``/themes/theme-preview-sample.txt``
	 * over wallpaper (or off-blue) so {@link RooTerm.Config.opacity} reads
	 * correctly in opaque prefs.
	 *
	 * Follows {@link RowThemeSelect} / opacity {@link RowScale} widgets (prefs
	 * local config is not updated on successful ``config_update``).
	 *
	 * == Example ==
	 *
	 * {{{
	 * var preview = new Dialog.RowThemePreview(config, theme_row, opacity_row);
	 * group.add(preview.row);
	 * preview.fill();
	 * }}}
	 */
	public class RowThemePreview : GLib.Object
	{
		/**
		 * Widget to add to an {@link Adw.PreferencesGroup}.
		 */
		public Adw.PreferencesRow row;
		public Config config;
		public RowThemeSelect theme_row;
		public RowScale opacity_row;
		public Vte.Terminal terminal;
		/**
		 * Solid off-blue or wallpaper; under the translucent VTE frame.
		 */
		public Gtk.Widget backdrop;
		public Gtk.Overlay overlay;
		public Gtk.Box vte_frame;
		public Gtk.CssProvider frame_css {
			get;
			set;
			default = new Gtk.CssProvider();
		}
		public Gdk.RGBA theme_fg;
		public Gdk.RGBA theme_bg;
		public Gdk.RGBA[] theme_palette;

		/**
		 * @param config Chrome settings (themes catalogue)
		 * @param theme_row Foreground theme selector
		 * @param opacity_row Appearance opacity scale
		 */
		public RowThemePreview(Config config, RowThemeSelect theme_row, RowScale opacity_row)
		{
			Object();
			this.config = config;
			this.theme_row = theme_row;
			this.opacity_row = opacity_row;
			this.config.themes.load();
			this.theme_fg = Gdk.RGBA();
			this.theme_bg = Gdk.RGBA();
			Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),
				this.frame_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
			this.backdrop = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
				css_classes = { "theme-preview-backdrop" }
			};
			this.frame_css.load_from_string(
				".theme-preview-backdrop { background-color: #3a4a5c; }"
				+ " .theme-preview-frame { background-color: transparent; }"
			);
			var uri = "";
			var schema_source = GLib.SettingsSchemaSource.get_default();
			var bg_schema = schema_source.lookup("org.gnome.desktop.background", true);
			if (bg_schema != null) {
				var bg = new GLib.Settings.full(bg_schema, null, null);
				uri = bg.get_string("picture-uri");
				var dark = bg.get_string("picture-uri-dark");
				var iface_schema = schema_source.lookup("org.gnome.desktop.interface", true);
				if (iface_schema != null) {
					var iface = new GLib.Settings.full(iface_schema, null, null);
					if (iface.get_string("color-scheme") == "prefer-dark" && dark != "") {
						uri = dark;
					}
				}
			}
			if (uri != "") {
				this.backdrop = new Gtk.Picture.for_file(GLib.File.new_for_uri(uri)) {
					content_fit = Gtk.ContentFit.COVER,
					can_shrink = true,
					hexpand = true,
					vexpand = true
				};
			}
			this.terminal = new Vte.Terminal() {
				sensitive = false,
				can_focus = false,
				hexpand = true,
				vexpand = true,
				cursor_blink_mode = Vte.CursorBlinkMode.OFF,
				scroll_on_output = false,
				scrollback_lines = 0
			};
			this.terminal.set_size(72, 10);
			this.terminal.set_input_enabled(false);
			this.terminal.feed(GLib.resources_lookup_data("/themes/theme-preview-sample.txt",
				GLib.ResourceLookupFlags.NONE).get_data());
			this.terminal.vadjustment.value = this.terminal.vadjustment.lower;
			this.vte_frame = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
				css_classes = { "theme-preview-frame" }
			};
			this.vte_frame.append(this.terminal);
			this.overlay = new Gtk.Overlay() {
				hexpand = true,
				vexpand = true,
				height_request = 220,
				child = this.backdrop
			};
			this.overlay.add_overlay(this.vte_frame);
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 10,
				margin_bottom = 12
			};
			box.append(new Gtk.Label("Theme preview") {
				xalign = 0f,
				css_classes = { "heading" }
			});
			box.append(this.overlay);
			this.row = new Adw.PreferencesRow() {
				activatable = false,
				child = box
			};
			this.theme_row.combo.notify["selected"].connect(() => {
				if (this.theme_row.loading) {
					return;
				}
				this.fill();
			});
			this.opacity_row.scale.value_changed.connect(() => {
				if (this.opacity_row.loading) {
					return;
				}
				this.fill();
			});
		}

		/**
		 * Apply colours from the theme combo and opacity scale.
		 */
		public void fill()
		{
			if (this.theme_row.combo.selected == Gtk.INVALID_LIST_POSITION) {
				return;
			}
			var theme = (Theme) this.theme_row.combo.selected_item;
			var opacity = (int) this.opacity_row.scale.get_value();
			this.theme_fg.parse(theme.foreground);
			this.theme_bg.parse(theme.background);
			this.theme_bg.alpha = opacity / 100.0f;
			var slots = theme.palette.split(";");
			this.theme_palette = new Gdk.RGBA[slots.length];
			for (var i = 0; i < slots.length; i++) {
				this.theme_palette[i].parse(slots[i]);
			}
			this.terminal.set_colors(this.theme_fg, this.theme_bg, this.theme_palette);
			this.terminal.set_clear_background(opacity >= 100);
			if (opacity >= 100) {
				this.frame_css.load_from_string(
					".theme-preview-backdrop { background-color: #3a4a5c; }"
					+ " .theme-preview-frame { background-color: transparent; }"
				);
				return;
			}
			this.frame_css.load_from_string(
				".theme-preview-backdrop { background-color: #3a4a5c; }"
				+ " .theme-preview-frame { background-color: rgba(%u,%u,%u,%.3f); }".printf(
					(uint) (this.theme_bg.red * 255.0f + 0.5f),
					(uint) (this.theme_bg.green * 255.0f + 0.5f),
					(uint) (this.theme_bg.blue * 255.0f + 0.5f), opacity / 100.0)
			);
		}
	}
}
