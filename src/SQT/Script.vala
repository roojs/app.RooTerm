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
	 * One ''script'' row.
	 *
	 * Same columns as Argus ``shared/SQT/Script.vala``.
	 * {@link path} is the list label. {@link body} is the shell text
	 * when {@link filetype} is ''inline''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * RooTerm.SQT.Script.init_db(db);
	 * var rows = new Gee.ArrayList<RooTerm.SQT.Script>();
	 * RooTerm.SQT.Script.query(db).select("", rows);
	 * }}}
	 */
	public class Script : GLib.Object
	{
		public int64 id { get; set; default = 0; }
		public int64 script_repository_id { get; set; default = 0; }
		public string path { get; set; default = ""; }
		public string filetype { get; set; default = ""; }
		public string platform { get; set; default = ""; }
		public string app { get; set; default = ""; }
		public string action { get; set; default = ""; }
		public string body { get; set; default = ""; }
		public bool allow_all { get; set; default = false; }
		/**
		 * Optional regex for the last command's output. Empty skips the check.
		 * Column name is ''success_regex''.
		 */
		public string success_regex { get; set; default = ""; }
		/**
		 * Host batch becomes root before the body.
		 * Column name is ''run_as_root''. Off leaves the login user.
		 */
		public bool run_as_root { get; set; default = false; }
		public int added_dt { get; set; default = 0; }
		public int updated_dt { get; set; default = 0; }
		public int deleted_dt { get; set; default = 0; }

		/**
		 * Rows in ''script''.
		 *
		 * @param db open database
		 * @return the query
		 */
		public static SQ.Query<Script> query(SQ.Database db)
		{
			return new SQ.Query<Script>(db, "script");
		}

		/**
		 * Create ''script''.
		 *
		 * @param db open database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS script (
					id                   INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					script_repository_id INTEGER NOT NULL DEFAULT 0,
					path                 TEXT NOT NULL DEFAULT '',
					filetype             TEXT NOT NULL DEFAULT '',
					platform             TEXT NOT NULL DEFAULT '',
					app                  TEXT NOT NULL DEFAULT '',
					action               TEXT NOT NULL DEFAULT '',
					body                 TEXT NOT NULL DEFAULT '',
					allow_all            INTEGER NOT NULL DEFAULT 0,
					success_regex        TEXT NOT NULL DEFAULT '',
					run_as_root          INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("script create failed: %s", db.db.errmsg());
			}
			db.db.exec(
				"ALTER TABLE script ADD COLUMN success_regex TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE script ADD COLUMN run_as_root INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			init_db_audit(db, "script");
		}
	}
}
