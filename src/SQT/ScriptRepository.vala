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
	 * One ''script_repository'' row.
	 *
	 * Same columns as Argus ``shared/SQT/ScriptRepository.vala``.
	 * A git clone. Not the scripts edited in the form.
	 *
	 * == Example ==
	 *
	 * {{{
	 * RooTerm.SQT.ScriptRepository.init_db(db);
	 * var rows = new Gee.ArrayList<RooTerm.SQT.ScriptRepository>();
	 * RooTerm.SQT.ScriptRepository.query(db).select("", rows);
	 * }}}
	 */
	public class ScriptRepository : GLib.Object
	{
		public int64 id { get; set; default = 0; }
		public string name { get; set; default = ""; }
		public string url { get; set; default = ""; }
		public string username { get; set; default = ""; }
		public string password { get; set; default = ""; }
		public string key { get; set; default = ""; }
		public int added_dt { get; set; default = 0; }
		public int updated_dt { get; set; default = 0; }
		public int deleted_dt { get; set; default = 0; }

		/**
		 * Rows in ''script_repository''.
		 *
		 * @param db open database
		 * @return the query
		 */
		public static SQ.Query<ScriptRepository> query(SQ.Database db)
		{
			return new SQ.Query<ScriptRepository>(db, "script_repository");
		}

		/**
		 * Create ''script_repository''.
		 *
		 * @param db open database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS script_repository (
					id        INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					name      TEXT NOT NULL DEFAULT '',
					url       TEXT NOT NULL DEFAULT '',
					username  TEXT NOT NULL DEFAULT '',
					password  TEXT NOT NULL DEFAULT '',
					key       TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("script_repository create failed: %s", db.db.errmsg());
			}
			init_db_audit(db, "script_repository");
		}
	}
}
