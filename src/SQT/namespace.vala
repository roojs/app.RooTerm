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

/**
 * SQL tables for the host tree and the Argus-compatible script library.
 *
 * {@link Connection} and {@link Forward} are the host tree.
 * {@link Script}, {@link ScriptPerm}, {@link ScriptRepository},
 * {@link Task}, and {@link TaskTarget} use the same columns as Argus
 * ``shared/SQT``. Those tables are created empty so a later phase can
 * fill them without a second schema.
 *
 * == Example ==
 *
 * {{{
 * var db = new SQ.Database(path, true);
 * RooTerm.SQT.init_db(db);
 * var rows = new Gee.ArrayList<RooTerm.SQT.Script>();
 * RooTerm.SQT.Script.query(db).select("", rows);
 * }}}
 */
namespace RooTerm.SQT
{
	/**
	 * Create every table this database owns.
	 *
	 * @param db open database
	 */
	public void init_db(SQ.Database db)
	{
		Connection.init_db(db);
		Forward.init_db(db);
		Script.init_db(db);
		ScriptPerm.init_db(db);
		ScriptRepository.init_db(db);
		Task.init_db(db);
		TaskTarget.init_db(db);
	}

	/**
	 * Add ''added_dt'', ''updated_dt'', and ''deleted_dt''.
	 *
	 * Call this after CREATE TABLE. A table that already has the
	 * columns is left as it is. Same columns as Argus
	 * {@link Argus.Shared.init_db_audit}.
	 *
	 * @param db open database
	 * @param table stored table name
	 */
	public void init_db_audit(SQ.Database db, string table)
	{
		var errmsg = "";
		db.db.exec(
			"ALTER TABLE " + table + " ADD COLUMN added_dt INTEGER NOT NULL DEFAULT 0;",
			null, out errmsg);
		db.db.exec(
			"ALTER TABLE " + table + " ADD COLUMN updated_dt INTEGER NOT NULL DEFAULT 0;",
			null, out errmsg);
		db.db.exec(
			"ALTER TABLE " + table + " ADD COLUMN deleted_dt INTEGER NOT NULL DEFAULT 0;",
			null, out errmsg);
	}
}
