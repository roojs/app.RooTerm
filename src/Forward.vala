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
	 * One SSH local port forward (``-L``).
	 */
	public class Forward : Object, Json.Serializable
	{
		public string local_host { get; set; default = "127.0.0.1"; }
		public int local_port { get; set; default = 0; }
		public string remote_host { get; set; default = ""; }
		public int remote_port { get; set; default = 0; }

		public unowned ParamSpec? find_property(string name)
		{
			return ((ObjectClass) typeof(Forward).class_ref()).find_property(name);
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
			return default_serialize_property(property_name, value, pspec);
		}

		public bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}
