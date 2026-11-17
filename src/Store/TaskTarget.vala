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
	 * Writes one {@link RooTerm.SQT.TaskTarget}.
	 *
	 * {@link save} inserts a new row or updates one that already
	 * has an id. {@link remove} deletes the row.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new RooTerm.Store.TaskTarget(db);
	 * store.save(target);
	 * }}}
	 */
	public class TaskTarget : GLib.Object
	{
		public SQ.Database db;

		/**
		 * @param db open database
		 */
		public TaskTarget(SQ.Database db)
		{
			Object();
			this.db = db;
		}

		/**
		 * Insert ''row'' or update it.
		 *
		 * @param row target being stored
		 */
		public void save(RooTerm.SQT.TaskTarget row)
		{
			var now = (int) new GLib.DateTime.now_local().to_unix();
			row.updated_dt = now;
			var is_new = row.id < 1;
			if (is_new) {
				row.added_dt = now;
				RooTerm.SQT.TaskTarget.query(this.db).insert(row);
			}
			if (!is_new) {
				RooTerm.SQT.TaskTarget.query(this.db).updateById(row);
			}
		}

		/**
		 * Delete ''row'' from ''task_target''.
		 *
		 * @param row target to remove
		 */
		public void remove(RooTerm.SQT.TaskTarget row)
		{
			if (row.id < 1) {
				return;
			}
			RooTerm.SQT.TaskTarget.query(this.db).deleteId(row.id);
		}
	}
}
