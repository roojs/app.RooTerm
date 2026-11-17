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

namespace RooTerm.Store
{
	/**
	 * Writes one {@link RooTerm.SQT.Task}.
	 *
	 * {@link save} inserts a new row or updates one that already
	 * has an id. Planning uses it for the draft task.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new RooTerm.Store.Task(db);
	 * store.save(task);
	 * }}}
	 */
	public class Task : GLib.Object
	{
		public SQ.Database db;

		/**
		 * @param db open database
		 */
		public Task(SQ.Database db)
		{
			Object();
			this.db = db;
		}

		/**
		 * Insert ''row'' or update it.
		 *
		 * @param row task being stored
		 */
		public void save(RooTerm.SQT.Task row)
		{
			var now = (int) new GLib.DateTime.now_local().to_unix();
			row.updated_dt = now;
			var is_new = row.id < 1;
			if (is_new) {
				row.added_dt = now;
				RooTerm.SQT.Task.query(this.db).insert(row);
			}
			if (!is_new) {
				RooTerm.SQT.Task.query(this.db).updateById(row);
			}
		}
	}
}
