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
	 * One ''forward'' row.
	 *
	 * One SSH local port forward (``-L``) on a {@link Connection}.
	 * {@link RooTerm.Host.Forward} extends this.
	 *
	 * == Example ==
	 *
	 * {{{
	 * RooTerm.SQT.Forward.init_db(db);
	 * var rows = new Gee.ArrayList<RooTerm.SQT.Forward>();
	 * RooTerm.SQT.Forward.query(db).select("ORDER BY position, id", rows);
	 * }}}
	 */
	public class Forward : GLib.Object
	{
		public int64 id { get; set; default = 0; }
		/**
		 * Parent {@link Connection.id}.
		 */
		public int64 connection_id { get; set; default = 0; }
		/**
		 * Order in the connection's forward list.
		 */
		public int position { get; set; default = 0; }
		public string local_host { get; set; default = "127.0.0.1"; }
		public int local_port { get; set; default = 0; }
		public string remote_host { get; set; default = ""; }
		public int remote_port { get; set; default = 0; }
		public int added_dt { get; set; default = 0; }
		public int updated_dt { get; set; default = 0; }
		public int deleted_dt { get; set; default = 0; }

		/**
		 * Rows in ''forward''.
		 *
		 * @param db open database
		 * @return the query
		 */
		public static SQ.Query<Forward> query(SQ.Database db)
		{
			return new SQ.Query<Forward>(db, "forward");
		}

		/**
		 * Create ''forward''.
		 *
		 * @param db open database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS forward (
					id            INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					connection_id INTEGER NOT NULL DEFAULT 0,
					position      INTEGER NOT NULL DEFAULT 0,
					local_host    TEXT NOT NULL DEFAULT '127.0.0.1',
					local_port    INTEGER NOT NULL DEFAULT 0,
					remote_host   TEXT NOT NULL DEFAULT '',
					remote_port   INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("forward create failed: %s", db.db.errmsg());
			}
			init_db_audit(db, "forward");
		}
	}
}
