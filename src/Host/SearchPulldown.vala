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

namespace RooTerm.Host
{
	/**
	 * Host search pulldown, adapted from OLLMchat ``SearchableDropdown`` /
	 * ``SearchablePulldown`` (entry + popover + filtered list).
	 * Up/Down highlight in the popover only; Enter/click opens or focuses the host.
	 */
	public class SearchPulldown : Gtk.Widget
	{
		public Gtk.Entry entry;
		protected Gtk.Image? arrow;
		public Gtk.Popover popup { get; private set; }
		protected Gtk.ListView list;
		protected TreeNodesFlat item_store;
		protected Gtk.FilterListModel filtered_items;
		protected Gtk.StringFilter string_filter;
		protected Gtk.SingleSelection selection;
		private string last_search_text = "";

		/**
		 * Placeholder text for the entry.
		 */
		public string placeholder_text { get; set; default = "Ctrl+Shift+O"; }

		/**
		 * Whether to show the arrow button.
		 */
		public bool show_arrow { get; set; default = true; }

		/**
		 * Emitted when the user commits a connection (open or focus).
		 */
		public signal void connection_selected(Connection connection);

		/**
		 * @param config Loaded RooTerm config (SSH hosts become list rows)
		 */
		public SearchPulldown(RooTerm.Config config)
		{
			Object();

			this.entry = new Gtk.Entry() {
				hexpand = true,
				tooltip_text = "Ctrl+Shift+O"
			};
			this.entry.set_parent(this);
			this.entry.placeholder_text = this.placeholder_text;
			this.entry.changed.connect(() => {
				this.on_entry_changed();
			});
			this.entry.add_css_class("suggestion");

			var key_controller = new Gtk.EventControllerKey();
			key_controller.propagation_phase = Gtk.PropagationPhase.CAPTURE;
			key_controller.key_pressed.connect((keyval, keycode, state) => {
				GLib.debug("search entry key keyval=%u name=%s code=%u state=%u",
					keyval, Gdk.keyval_name(keyval), keycode, (uint) state);
				return this.on_key_pressed(keyval, keycode, state);
			});
			this.entry.add_controller(key_controller);

			var focus_controller = new Gtk.EventControllerFocus();
			focus_controller.leave.connect(() => {
				GLib.debug("search entry leave popup=%d focused=%d",
					this.popup.visible ? 1 : 0, this.entry.has_focus ? 1 : 0);
				if (!this.popup.visible) {
					return;
				}
				GLib.Idle.add(() => {
					GLib.debug("search leave idle entry_focus=%d popup=%d",
						this.entry.has_focus ? 1 : 0, this.popup.visible ? 1 : 0);
					if (this.entry.has_focus) {
						return false;
					}
					this.set_popup_visible(false);
					return false;
				});
			});
			this.entry.add_controller(focus_controller);

			this.item_store = config.tree.flat;

			this.string_filter = new Gtk.StringFilter(
				new Gtk.PropertyExpression(typeof(Connection), null, "search-name")
			) {
				match_mode = Gtk.StringFilterMatchMode.SUBSTRING,
				ignore_case = true
			};

			this.filtered_items = new Gtk.FilterListModel(this.item_store, this.string_filter);

			this.selection = new Gtk.SingleSelection(this.filtered_items) {
				autoselect = false,
				can_unselect = true,
				selected = Gtk.INVALID_LIST_POSITION
			};

			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START,
					xalign = 0.0f,
					hexpand = true
				};
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = label;
			});
			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				var label = list_item.get_data<Gtk.Label>("label");
				if (label == null) {
					return;
				}
				list_item.item.bind_property("search-name", label, "label", GLib.BindingFlags.SYNC_CREATE);
				list_item.item.bind_property("search-name", label, "tooltip-text", GLib.BindingFlags.SYNC_CREATE);
			});

			this.popup = new Gtk.Popover() {
				position = Gtk.PositionType.BOTTOM,
				autohide = false,
				has_arrow = false,
				halign = Gtk.Align.START,
				can_focus = false
			};
			this.popup.set_parent(this);
			this.popup.add_css_class("menu");

			var sw = new Gtk.ScrolledWindow() {
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				max_content_height = 400,
				propagate_natural_height = true,
				propagate_natural_width = false,
				can_focus = false
			};

			this.list = new Gtk.ListView(this.selection, factory) {
				single_click_activate = true,
				can_focus = false
			};
			this.list.activate.connect((position) => {
				this.set_popup_visible(false);
				this.on_selected();
			});

			sw.child = this.list;

			var popup_wrapper = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			popup_wrapper.append(sw);

			var wrapper_scroll_controller = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.BOTH_AXES |
				Gtk.EventControllerScrollFlags.DISCRETE |
				Gtk.EventControllerScrollFlags.KINETIC
			);
			wrapper_scroll_controller.scroll.connect((dx, dy) => {
				var vadjustment = sw.vadjustment;
				if (vadjustment != null && dy != 0) {
					var current_value = vadjustment.value;
					var new_value = current_value + dy * vadjustment.step_increment * 3;
					vadjustment.value = new_value.clamp(vadjustment.lower, vadjustment.upper - vadjustment.page_size);
				}
				return true;
			});
			popup_wrapper.add_controller(wrapper_scroll_controller);

			this.popup.child = popup_wrapper;

			this.notify["show-arrow"].connect(() => {
				this.update_arrow();
			});

			this.notify["placeholder-text"].connect(() => {
				if (this.entry.text == "") {
					this.entry.placeholder_text = this.placeholder_text;
				}
			});

			this.update_arrow();

			var widget_scroll_controller = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.BOTH_AXES |
				Gtk.EventControllerScrollFlags.DISCRETE |
				Gtk.EventControllerScrollFlags.KINETIC
			);
			widget_scroll_controller.scroll.connect((dx, dy) => {
				if (this.popup.visible) {
					return true;
				}
				return false;
			});
			widget_scroll_controller.propagation_phase = Gtk.PropagationPhase.BUBBLE;
			this.add_controller(widget_scroll_controller);
		}

		public override bool grab_focus()
		{
			return this.entry.grab_focus();
		}

		public override void dispose()
		{
			if (this.entry != null) {
				this.entry.unparent();
			}
			if (this.arrow != null) {
				this.arrow.unparent();
			}
			if (this.popup != null) {
				this.popup.unparent();
			}
			base.dispose();
		}

		public override void measure(Gtk.Orientation orientation,
			int for_size, out int minimum,
			out int natural, out int minimum_baseline,
			out int natural_baseline)
		{
			var arrow_min = 0;
			var arrow_nat = 0;

			this.entry.measure(orientation, for_size,
				out minimum, out natural,
				out minimum_baseline, out natural_baseline);

			if (this.arrow != null && this.arrow.visible) {
				this.arrow.measure(orientation, for_size,
					out arrow_min, out arrow_nat, null, null);
			}

			if (orientation == Gtk.Orientation.HORIZONTAL) {
				minimum += arrow_nat;
				natural += arrow_nat;
			}
		}

		public override void size_allocate(int width, int height, int baseline)
		{
			var arrow_min = 0;
			var arrow_nat = 0;

			if (this.arrow != null && this.arrow.visible) {
				this.arrow.measure(Gtk.Orientation.HORIZONTAL, -1,
					out arrow_min, out arrow_nat, null, null);
			}

			this.entry.allocate(width, height, baseline, null);

			if (this.arrow != null && this.arrow.visible && arrow_nat > 0) {
				this.entry.set_margin_end(arrow_nat);
			} else {
				this.entry.set_margin_end(0);
			}

			if (this.arrow != null && this.arrow.visible) {
				var arrow_point = new Graphene.Point() {
					x = (float) (width - arrow_nat),
					y = 0.0f
				};
				var arrow_transform = new Gsk.Transform();
				arrow_transform = arrow_transform.translate(arrow_point);
				this.arrow.allocate(arrow_nat, height, baseline, arrow_transform);
			}

			this.popup.set_size_request(width * 2, -1);
		}

		protected void update_arrow()
		{
			if (this.show_arrow && this.arrow == null) {
				this.arrow = new Gtk.Image.from_icon_name("pan-down-symbolic") {
					tooltip_text = "Show hosts"
				};
				this.arrow.set_parent(this);

				var gesture = new Gtk.GestureClick();
				gesture.released.connect(() => {
					this.set_popup_visible(!this.popup.visible);
				});
				this.arrow.add_controller(gesture);
				return;
			}
			if (!this.show_arrow && this.arrow != null) {
				this.arrow.unparent();
				this.arrow = null;
			}
		}

		protected void set_popup_visible(bool visible)
		{
			GLib.debug("search popup request visible=%d was=%d", visible ? 1 : 0, this.popup.visible ? 1 : 0);
			if (this.popup.visible == visible) {
				return;
			}

			if (visible) {
				var root = this.get_root();
				if (root == null || !(root is Gtk.Window)) {
					GLib.debug("search popup open aborted no root window");
					return;
				}

				this.selection.selected = Gtk.INVALID_LIST_POSITION;

				if (!this.entry.has_focus) {
					this.entry.grab_focus();
				}
				this.entry.set_position(-1);
				this.entry.select_region(-1, -1);
				this.popup.popup();
				GLib.debug("search popup opened matches=%u", this.filtered_items.get_n_items());

				GLib.Idle.add(() => {
					var scrolled = this.popup.child as Gtk.ScrolledWindow;
					if (scrolled == null && this.popup.child is Gtk.Box) {
						var outer = this.popup.child as Gtk.Box;
						scrolled = outer.get_first_child() as Gtk.ScrolledWindow;
					}
					if (scrolled != null) {
						scrolled.vadjustment.value = scrolled.vadjustment.lower;
					}
					return false;
				});
				return;
			}

			this.popup.popdown();
			GLib.debug("search popup closed");
		}

		protected void on_entry_changed()
		{
			var search_text = this.entry.text;

			if (search_text == this.last_search_text) {
				return;
			}

			this.last_search_text = search_text;

			if (search_text == "") {
				this.string_filter.search = "";
				this.entry.placeholder_text = this.placeholder_text;
				if (this.popup.visible) {
					this.set_popup_visible(false);
				}
				return;
			}

			this.string_filter.search = search_text;
			this.entry.placeholder_text = "";

			if (this.filtered_items.get_n_items() == 0) {
				if (this.popup.visible) {
					this.set_popup_visible(false);
				}
				return;
			}

			this.set_popup_visible(true);
			this.selection.selected = 0;
			this.list.scroll_to(0, Gtk.ListScrollFlags.SELECT, null);
		}

		protected bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state)
		{
			var mods = state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK);
			if (mods != 0) {
				GLib.debug("search key ignored mods=%u", (uint) mods);
				return false;
			}

			if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter || keyval == Gdk.Key.ISO_Enter) {
				GLib.debug("search enter popup=%d selected=%u",
					this.popup.visible ? 1 : 0, this.selection.selected);
				if (this.popup.visible) {
					if (this.selection.selected == Gtk.INVALID_LIST_POSITION && this.filtered_items.get_n_items() > 0) {
						this.selection.selected = 0;
					}
					this.set_popup_visible(false);
					this.on_selected();
					return true;
				}
				return false;
			}

			if (keyval == Gdk.Key.Escape) {
				if (this.popup.visible) {
					this.set_popup_visible(false);
					return true;
				}
				return false;
			}

			if (keyval == Gdk.Key.Tab || keyval == Gdk.Key.KP_Tab || keyval == Gdk.Key.ISO_Left_Tab) {
				if (this.popup.visible) {
					this.set_popup_visible(false);
					return false;
				}
				return false;
			}

			var matches = this.filtered_items.get_n_items();
			if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up || keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
				GLib.debug("search arrow name=%s popup=%d matches=%u selected=%u text_len=%d",
					Gdk.keyval_name(keyval), this.popup.visible ? 1 : 0, matches, this.selection.selected, this.entry.text.length);
				if (!this.popup.visible && this.entry.text.length == 0) {
					this.string_filter.search = "";
					matches = this.filtered_items.get_n_items();
					GLib.debug("search arrow empty-query matches=%u", matches);
				}
				if (matches == 0) {
					GLib.debug("search arrow abort no matches");
					return false;
				}
				if (!this.popup.visible) {
					this.set_popup_visible(true);
					if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
						this.selection.selected = matches - 1;
					}
					if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
						this.selection.selected = 0;
					}
					GLib.debug("search arrow opened selected=%u popup=%d",
						this.selection.selected, this.popup.visible ? 1 : 0);
					this.list.scroll_to(this.selection.selected, Gtk.ListScrollFlags.SELECT, null);
					return true;
				}
				var selected = this.selection.selected;
				if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
					if (selected == Gtk.INVALID_LIST_POSITION || selected == 0) {
						selected = matches - 1;
					} else {
						selected--;
					}
				}
				if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
					if (selected == Gtk.INVALID_LIST_POSITION || selected >= matches - 1) {
						selected = 0;
					} else {
						selected++;
					}
				}
				this.selection.selected = selected;
				GLib.debug("search arrow moved selected=%u item=%s",
					selected, this.selection.selected_item != null ? ((Connection) this.selection.selected_item).name : "");
				this.list.scroll_to(selected, Gtk.ListScrollFlags.SELECT, null);
				return true;
			}

			return false;
		}

		protected void on_selected()
		{
			var conn = this.selection.selected_item as Connection;
			if (conn == null) {
				return;
			}
			this.entry.text = "";
			this.connection_selected(conn);
		}
	}
}
