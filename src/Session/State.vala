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

namespace RooTerm.Session
{
	/**
	 * Background mark for an open terminal tab in the host tree.
	 * Active emphasis is {@link Terminal.Base.tree_active}, not a stored state.
	 *
	 * == Example ==
	 *
	 * {{{
	 * if (term.state == State.READY) {
	 *     // unread output while unfocused
	 * }
	 * }}}
	 */
	public enum State
	{
		IDLE,
		BUSY,
		READY,
		/**
		 * Child process has exited (SSH); tab may still be open for reconnect / close.
		 */
		EXITED
	}
}
