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
	 * One ''task'' row.
	 *
	 * Same columns as Argus ``shared/SQT/Task.vala``.
	 * The machines it runs on are {@link TaskTarget}.
	 * {@link command} holds the script body copied at execute time.
	 * {@link is_draft} stays true while the batch is still planning.
	 *
	 * == Example ==
	 *
	 * {{{
	 * RooTerm.SQT.Task.init_db(db);
	 * var rows = new Gee.ArrayList<RooTerm.SQT.Task>();
	 * RooTerm.SQT.Task.query(db).select("", rows);
	 * }}}
	 */
	public class Task : GLib.Object
	{
		public int64 id { get; set; default = 0; }
		public string name { get; set; default = ""; }
		public bool is_script { get; set; default = false; }
		public string command { get; set; default = ""; }
		public int64 script_id { get; set; default = 0; }
		public int64 dist_version_id { get; set; default = 0; }
		public string run_as { get; set; default = ""; }
		public bool is_template { get; set; default = false; }
		public bool is_draft { get; set; default = true; }
		public int64 scheduled { get; set; default = 0; }
		public int64 completed { get; set; default = 0; }
		public int created_by { get; set; default = 0; }
		public int approved_by { get; set; default = 0; }
		public string controller_sig { get; set; default = ""; }
		public string server_sig { get; set; default = ""; }
		public int64 expires_at { get; set; default = 0; }
		public int added_dt { get; set; default = 0; }
		public int updated_dt { get; set; default = 0; }
		public int deleted_dt { get; set; default = 0; }

		/**
		 * Rows in ''task''.
		 *
		 * @param db open database
		 * @return the query
		 */
		public static SQ.Query<Task> query(SQ.Database db)
		{
			return new SQ.Query<Task>(db, "task");
		}

		/**
		 * Create ''task''.
		 *
		 * @param db open database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS task (
					id               INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					name             TEXT NOT NULL DEFAULT '',
					is_script        INTEGER NOT NULL DEFAULT 0,
					command          TEXT NOT NULL DEFAULT '',
					script_id        INTEGER NOT NULL DEFAULT 0,
					dist_version_id  INTEGER NOT NULL DEFAULT 0,
					run_as           TEXT NOT NULL DEFAULT '',
					is_template      INTEGER NOT NULL DEFAULT 0,
					is_draft         INTEGER NOT NULL DEFAULT 1,
					scheduled        INT64 NOT NULL DEFAULT 0,
					completed        INT64 NOT NULL DEFAULT 0,
					created_by       INTEGER NOT NULL DEFAULT 0,
					approved_by      INTEGER NOT NULL DEFAULT 0,
					controller_sig   TEXT NOT NULL DEFAULT '',
					server_sig       TEXT NOT NULL DEFAULT '',
					expires_at       INT64 NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("task create failed: %s", db.db.errmsg());
			}
			init_db_audit(db, "task");
		}
	}
}
