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

namespace RooTerm.SQT
{
	/**
	 * One ''connection'' row.
	 *
	 * A host, group, localhost, path, or LXC container.
	 * {@link RooTerm.Host.Connection} extends this and adds the live
	 * tree fields. Passwords stay in libsecret, keyed by {@link uuid}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * RooTerm.SQT.Connection.init_db(db);
	 * var rows = new Gee.ArrayList<RooTerm.SQT.Connection>();
	 * RooTerm.SQT.Connection.query(db).select("ORDER BY position, id", rows);
	 * }}}
	 */
	public class Connection : GLib.Object
	{
		public int64 id { get; set; default = 0; }
		public string uuid { get; set; default = ""; }
		public string parent_uuid { get; set; default = ""; }
		/**
		 * Sibling order. Was the JSON array index.
		 */
		public int position { get; set; default = 0; }
		public string name { get; set; default = ""; }
		/**
		 * Absolute working directory for a localhost path. Empty otherwise.
		 */
		public string cwd { get; set; default = ""; }
		/**
		 * Whether this row is expanded in the host tree.
		 * Saving it on toggle is parked.
		 */
		public bool expanded { get; set; default = true; }
		/**
		 * {@link RooTerm.Host.ConnectionKind} as an integer.
		 * Not an enum property: ocsqlite aborts when an enum value is 0,
		 * and HOST is 0.
		 */
		public int kind_code { get; set; default = 0; }
		public string method { get; set; default = ""; }
		public string host { get; set; default = ""; }
		public int port { get; set; default = 22; }
		public string user { get; set; default = ""; }
		public string auth { get; set; default = ""; }
		public string public_key { get; set; default = ""; }
		/**
		 * Old private-key path still on the server.
		 * The local identity file is not deleted.
		 */
		public string retire_key { get; set; default = ""; }
		public string options { get; set; default = ""; }
		public bool deleted { get; set; default = false; }
		/**
		 * After shell login, run ``sudo -i`` and feed the connection password.
		 */
		public bool sudo_after_login { get; set; default = false; }
		/**
		 * Host may have LXC containers.
		 */
		public bool lxc_host { get; set; default = false; }
		/**
		 * Container name for ``lxc-console -n`` on an interactive session.
		 */
		public string lxc_name { get; set; default = ""; }
		public int added_dt { get; set; default = 0; }
		public int updated_dt { get; set; default = 0; }
		public int deleted_dt { get; set; default = 0; }

		/**
		 * Rows in ''connection''.
		 *
		 * @param db open database
		 * @return the query
		 */
		public static SQ.Query<Connection> query(SQ.Database db)
		{
			return new SQ.Query<Connection>(db, "connection");
		}

		/**
		 * Create ''connection''.
		 *
		 * @param db open database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS connection (
					id               INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					uuid             TEXT NOT NULL DEFAULT '',
					parent_uuid      TEXT NOT NULL DEFAULT '',
					position         INTEGER NOT NULL DEFAULT 0,
					name             TEXT NOT NULL DEFAULT '',
					cwd              TEXT NOT NULL DEFAULT '',
					expanded         INTEGER NOT NULL DEFAULT 1,
					kind_code        INTEGER NOT NULL DEFAULT 0,
					method           TEXT NOT NULL DEFAULT '',
					host             TEXT NOT NULL DEFAULT '',
					port             INTEGER NOT NULL DEFAULT 22,
					user             TEXT NOT NULL DEFAULT '',
					auth             TEXT NOT NULL DEFAULT '',
					public_key       TEXT NOT NULL DEFAULT '',
					retire_key       TEXT NOT NULL DEFAULT '',
					options          TEXT NOT NULL DEFAULT '',
					deleted          INTEGER NOT NULL DEFAULT 0,
					sudo_after_login INTEGER NOT NULL DEFAULT 0,
					lxc_host         INTEGER NOT NULL DEFAULT 0,
					lxc_name         TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("connection create failed: %s", db.db.errmsg());
			}
			init_db_audit(db, "connection");
		}
	}
}
