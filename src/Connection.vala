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
	 * Connection or group (``is_group``); JSON via {@link Json.Serializable}.
	 */
	public class Connection : Object, Json.Serializable
	{
		public string uuid { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public bool is_group { get; set; default = false; }
		public string parent_uuid { get; set; default = ""; }
		public string method { get; set; default = ""; }
		public string host { get; set; default = ""; }
		public int port { get; set; default = 22; }
		public string user { get; set; default = ""; }
		public string pass { get; set; default = ""; }
		public string passphrase { get; set; default = ""; }
		public string auth { get; set; default = ""; }
		public string public_key { get; set; default = ""; }
		public string options { get; set; default = ""; }
		public bool deleted { get; set; default = false; }
		public Gee.ArrayList<Forward> forwards {
			get;
			set;
			default = new Gee.ArrayList<Forward>();
		}
		public int open_count { get; set; default = 0; }
		public int active_tab { get; set; default = -1; }
		public Gee.ArrayList<string> tab_titles {
			get;
			set;
			default = new Gee.ArrayList<string>();
		}
		public Gee.ArrayList<Connection> children {
			get;
			set;
			default = new Gee.ArrayList<Connection>();
		}

		public unowned ParamSpec? find_property(string name)
		{
			return ((ObjectClass) typeof(Connection).class_ref()).find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			((Object) this).set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			((Object) this).get_property(pspec.get_name(), ref val);
			return val;
		}

		public Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "pass":
				case "passphrase":
				case "open-count":
				case "active-tab":
				case "tab-titles":
				case "children":
					return null;
				case "forwards":
					var arr = new Json.Array();
					foreach (var fwd in this.forwards) {
						arr.add_element(Json.gobject_serialize(fwd));
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.take_array(arr);
					return node;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "forwards") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			this.forwards.clear();
			if (property_node.get_node_type() == Json.NodeType.ARRAY) {
				var json_array = property_node.get_array();
				for (var i = 0; i < json_array.get_length(); i++) {
					var fwd = Json.gobject_deserialize(typeof(Forward), json_array.get_element(i)) as Forward;
					if (fwd == null) {
						continue;
					}
					this.forwards.add(fwd);
				}
			}
			value = Value(typeof(Gee.ArrayList));
			value.set_object(this.forwards);
			return true;
		}
	}
}
