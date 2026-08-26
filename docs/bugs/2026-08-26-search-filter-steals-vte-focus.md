# Search filter steals VTE focus

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ✔️ fix applied — awaiting user verify

**Started:** 2026-08-26

---

## Problem

- **🔷** Typing in the host search box (e.g. `B`) moves keyboard focus into
  the VTE instead of leaving it on the search entry.
- **🔷** Expected: filter the tree; keep caret in search; Up/Down walk
  `search_target`; Enter picks.
- **🔷** Blocking flag while the filter runs: do not refocus the VTE.

## Evidence

- **ℹ️** `Host.Tree` `notify["search"]` refilters + `expand_all` (and may
  set `show_all`).
- **ℹ️** `Gtk.SingleSelection` `selected` then notifies — items added/removed
  or the selected row remaps.
- **ℹ️** That handler emits `connection_highlighted` →
  `MainWindow` → `sessions.focus()` → `terminal.grab_focus()`.
- **ℹ️** Same handler can also clear `search` when `show_all` or search is
  on and the row has sessions.
- **ℹ️** `expand_all` continues on `Idle.add`, so selection can fire after
  the search notify returns.
- **ℹ️** 0.22 (`docs/plans/0.22-search-result-cursor.md`): focus stays in
  the search entry; ListView selection is the active terminal, not the walk.

## Root cause

- **✔️** Filter-driven ListView selection is treated as a user highlight.
- **✔️** That path is what grabs VTE focus (and can clear the query).
- **🚫** Not Up/Down/`search_step` — those do not change `selection`.

## Proposed fix

- **🔷** `TreeNodes.expand_queue` counts in-flight expand work. A layer that
  schedules an idle increments; that idle decrements after it dispatches
  children. Nested `children.expand_all(counter)` share the window tree
  so it is one queue.
- **🔷** `Host.Tree` raises `block_vte` at the start of `notify["search"]`.
- **🔷** `notify["expand-queue"]`: when the count hits 0 and `block_vte`,
  `Idle.add` unblocks (and `search_step` if the query is non-empty).
- **🔷** If `expand_all` had nothing to queue, `expand_queue` stays 0 — same
  idle from the search handler (no notify).
- **🔷** `notify["selected"]` returns immediately when `block_vte`.
- **🚫** `Priority.LOW` idle — inferred drain, not a completion count.
- **🚫** List `GestureClick` whose only job is to clear the flag.

### `src/Host/TreeNodes.vala`

#### Add — `expand_queue` next to `num_open`

```vala
		/**
		 * In-flight {@link expand_all} work on this list (the window tree).
		 * Each layer that schedules an idle increments; that idle decrements
		 * after dispatching children. Nested calls pass this same instance
		 * so the count is one queue, not per layer.
		 */
		public int expand_queue { get; set; default = 0; }
```

#### Replace with — `expand_all` bumps the window-tree queue

```vala
		public void expand_all(TreeNodes? counter = null)
		{
			var owner = counter != null ? counter : this;
			if (this.expandable.size == 0) {
				return;
			}
			owner.expand_queue++;
			foreach (var conn in this.expandable) {
				if (conn.tree_row == null) {
					continue;
				}
				conn.tree_row.expanded = true;
			}
			GLib.Idle.add(() => {
				foreach (var conn in this.expandable) {
					conn.children.expand_all(owner);
				}
				owner.expand_queue--;
				return false;
			});
		}
```

### `src/Host/Tree.vala`

#### Add — `notify["expand-queue"]` before `open_changed`

When the queue hits 0 while search blocked the VTE, one idle then
unblock / first-hit cursor.

### `src/Host/Tree.vala`

#### Add — flag next to `search_target`

```vala
		/**
		 * True while search is refiltering / expanding the tree.
		 * Selection changes from that must not emit
		 * {@link connection_highlighted} (VTE grab) or clear search.
		 */
		private bool block_vte = false;
```

#### Replace with — `notify["search"]`: raise before refilter, drop on idle

Empty query: raise, refilter, `Idle.add_full(LOW)` clear. Non-empty:
raise, refilter, `Idle.add_full(LOW)` → `search_step` then clear.

#### Add — `notify["selected"]`: skip while blocked

```vala
			this.selection.notify["selected"].connect(() => {
				if (this.block_vte) {
					GLib.debug("block_vte skip selected search=%s", this.search);
					return;
				}
```

---

## Attempts / changelog

- **✔️** 2026-08-26 — `block_vte` around search refilter.
- **🚫** Capture `GestureClick` to clear the flag — too broad; removed.
- **🚫** `Priority.LOW` idle after expand — still inferred, not counted.
- **✔️** 2026-08-26 — `expand_queue`; unblock on 0 via `Idle.add`.
- **⏳** Confirm: type in search, caret stays; Enter / click still focus VTE.

## Next

- **⏳** **🔷** User verify on device (`--debug` → skip line while typing).
