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
	 * One ''task_target'' row.
	 *
	 * Same columns as Argus ``shared/SQT/TaskTarget.vala``.
	 * One machine a {@link Task} runs on. {@link agent_id} stores
	 * {@link Connection.id} until a real agent id exists.
	 * {@link identifier} counts how many script lines have finished.
	 *
	 * == Example ==
	 *
	 * {{{
	 * RooTerm.SQT.TaskTarget.init_db(db);
	 * var rows = new Gee.ArrayList<RooTerm.SQT.TaskTarget>();
	 * RooTerm.SQT.TaskTarget.query(db).select("", rows);
	 * }}}
	 */
	public class TaskTarget : GLib.Object
	{
		public int64 id { get; set; default = 0; }
		public int64 task_id { get; set; default = 0; }
		public int64 agent_id { get; set; default = 0; }
		public int64 scheduled { get; set; default = 0; }
		public int64 started { get; set; default = 0; }
		public int64 ended { get; set; default = 0; }
		public int success { get; set; default = 0; }
		public bool is_cancelled { get; set; default = false; }
		public bool is_watched { get; set; default = false; }
		public int timeout { get; set; default = 0; }
		public int identifier { get; set; default = 0; }
		public string log_dir { get; set; default = ""; }
		public int added_dt { get; set; default = 0; }
		public int updated_dt { get; set; default = 0; }
		public int deleted_dt { get; set; default = 0; }

		/**
		 * Rows in ''task_target''.
		 *
		 * @param db open database
		 * @return the query
		 */
		public static SQ.Query<TaskTarget> query(SQ.Database db)
		{
			return new SQ.Query<TaskTarget>(db, "task_target");
		}

		/**
		 * Create ''task_target''.
		 *
		 * @param db open database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS task_target (
					id           INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					task_id      INTEGER NOT NULL DEFAULT 0,
					agent_id     INTEGER NOT NULL DEFAULT 0,
					scheduled    INT64 NOT NULL DEFAULT 0,
					started      INT64 NOT NULL DEFAULT 0,
					ended        INT64 NOT NULL DEFAULT 0,
					success      INTEGER NOT NULL DEFAULT 0,
					is_cancelled INTEGER NOT NULL DEFAULT 0,
					is_watched   INTEGER NOT NULL DEFAULT 0,
					timeout      INTEGER NOT NULL DEFAULT 0,
					identifier   INTEGER NOT NULL DEFAULT 0,
					log_dir      TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("task_target create failed: %s", db.db.errmsg());
			}
			init_db_audit(db, "task_target");
		}
	}
}
