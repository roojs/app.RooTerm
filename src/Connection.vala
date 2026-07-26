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
	 * Ásbrú connection or group (``is_group``).
	 */
	public class Connection : GLib.Object
	{
		public string uuid = "";
		public string name { get; set; default = ""; }
		public bool is_group = false;
		public string parent_uuid = "";
		public string method = "";
		public string ip = "";
		public int port = 22;
		public string user = "";
		public string pass = "";
		public string passphrase = "";
		public string auth_type = "";
		public string public_key = "";
		public string options = "";
		/**
		 * Soft-deleted hosts/groups are hidden from tree and search.
		 */
		public bool deleted = false;
		/**
		 * Local port forwards for ``ssh -L``.
		 */
		public Gee.ArrayList<Forward> forwards {
			get;
			set;
			default = new Gee.ArrayList<Forward>();
		}
		/**
		 * Open terminal tabs for this host (one tree icon each).
		 */
		public int open_count { get; set; default = 0; }
		/**
		 * Index of the focused tab for this host (``-1`` if none).
		 */
		public int active_tab { get; set; default = -1; }
		/**
		 * Per-tab display labels (same order as tree session icons).
		 */
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
	}
}
