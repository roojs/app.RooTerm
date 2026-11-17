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
	 * Script library.
	 *
	 * A {@link GLib.ListModel} of {@link RooTerm.SQT.Script}.
	 * {@link load} reads rows whose ''deleted_dt'' is 0.
	 * {@link save} inserts a new row or updates one that already
	 * has an id, then reloads. {@link remove} sets ''deleted_dt''
	 * so the row stays for any task that points at it.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new RooTerm.Store.Script(db);
	 * store.load();
	 * }}}
	 */
	public class Script : GLib.Object, GLib.ListModel
	{
		public SQ.Database db;
		private Gee.ArrayList<RooTerm.SQT.Script> items_store {
			get; set; default = new Gee.ArrayList<RooTerm.SQT.Script>();
		}

		/**
		 * Rows from the last {@link load}. This list is the model.
		 */
		public Gee.ArrayList<RooTerm.SQT.Script> items {
			get {
				return this.items_store;
			}
			private set {
				if (this.items_store == value) {
					return;
				}
				var removed = (uint) this.items_store.size;
				this.items_store = value;
				this.items_changed(0, removed, (uint) value.size);
			}
		}

		/**
		 * True after a load with no rows.
		 */
		public bool empty { get; private set; default = false; }

		/**
		 * @param db open database
		 */
		public Script(SQ.Database db)
		{
			Object();
			this.db = db;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(RooTerm.SQT.Script);
		}

		/**
		 * Number of scripts in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Script at ''position''.
		 *
		 * @param position zero-based index
		 * @return the row, or null when ''position'' is past the end
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Replace {@link items} with the scripts that are not deleted.
		 */
		public void load()
		{
			var rows = new Gee.ArrayList<RooTerm.SQT.Script>();
			RooTerm.SQT.Script.query(this.db).select(
				"WHERE deleted_dt = 0 ORDER BY path", rows);
			this.empty = rows.size == 0;
			this.items = rows;
		}

		/**
		 * Insert ''row'' or update it, then {@link load}.
		 *
		 * A new row is stored as filetype ''inline''.
		 *
		 * @param row script being edited
		 */
		public void save(RooTerm.SQT.Script row)
		{
			var now = (int) new GLib.DateTime.now_local().to_unix();
			row.updated_dt = now;
			if (row.filetype == "") {
				row.filetype = "inline";
			}
			var is_new = row.id < 1;
			if (is_new) {
				row.added_dt = now;
				RooTerm.SQT.Script.query(this.db).insert(row);
			}
			if (!is_new) {
				RooTerm.SQT.Script.query(this.db).updateById(row);
			}
			this.load();
		}

		/**
		 * Mark ''row'' deleted and {@link load}. The row stays in the table.
		 *
		 * @param row script to hide
		 */
		public void remove(RooTerm.SQT.Script row)
		{
			if (row.id < 1) {
				return;
			}
			row.deleted_dt = (int) new GLib.DateTime.now_local().to_unix();
			row.updated_dt = row.deleted_dt;
			RooTerm.SQT.Script.query(this.db).updateById(row);
			this.load();
		}
	}
}
