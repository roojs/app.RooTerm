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
	 * One ''script_perm'' row.
	 *
	 * Same columns as Argus ``shared/SQT/ScriptPerm.vala``.
	 * Permits a {@link Script} on a machine when {@link Script.allow_all}
	 * is false.
	 *
	 * == Example ==
	 *
	 * {{{
	 * RooTerm.SQT.ScriptPerm.init_db(db);
	 * var rows = new Gee.ArrayList<RooTerm.SQT.ScriptPerm>();
	 * RooTerm.SQT.ScriptPerm.query(db).select("", rows);
	 * }}}
	 */
	public class ScriptPerm : GLib.Object
	{
		public int64 id { get; set; default = 0; }
		public int64 script_id { get; set; default = 0; }
		public int64 agent_id { get; set; default = 0; }
		public int added_dt { get; set; default = 0; }
		public int updated_dt { get; set; default = 0; }
		public int deleted_dt { get; set; default = 0; }

		/**
		 * Rows in ''script_perm''.
		 *
		 * @param db open database
		 * @return the query
		 */
		public static SQ.Query<ScriptPerm> query(SQ.Database db)
		{
			return new SQ.Query<ScriptPerm>(db, "script_perm");
		}

		/**
		 * Create ''script_perm''.
		 *
		 * @param db open database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS script_perm (
					id         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					script_id  INTEGER NOT NULL DEFAULT 0,
					agent_id   INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("script_perm create failed: %s", db.db.errmsg());
			}
			init_db_audit(db, "script_perm");
		}
	}
}
