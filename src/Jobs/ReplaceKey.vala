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

namespace RooTerm
{
	/**
	 * Replace-with-passphrased-key: same terminal flow as {@link SetupKey}.
	 *
	 * Sets ``install_identity`` in the ctor; set {@link old_identity} for ConnDialog.
	 */
	public class ReplaceKey : SetupKey
	{
		/**
		 * Previous identity to retire later (ConnDialog stores on success).
		 */
		public string old_identity = "";

		/**
		 * @param window Main window
		 * @param connection Host the job acts on
		 * @param install_identity Private key path for ``ssh-copy-id``
		 */
		public ReplaceKey(MainWindow window, Connection connection, string install_identity)
		{
			base(window, connection);
			this.stream.install_identity = install_identity;
		}
	}
}
