# Tree expand shows only a few children until collapse/re-expand

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ✅ FIXED — user closed out 2026-08-14

**Started:** 2026-08-04

---

## Problem

- **🔷** Expanding a tree row is buggy: often only a **few** children appear.
- **🔷** Collapse the same row, expand again → more (or the full set) of children show up.
- **🔷** Feels intermittent / “habit” of under-filling on first expand.
- **🔷** 2026-08-14 — reproduced: leave everything expanded, quit, reopen; **`all`** (large group) under-fills.

## Evidence

- **ℹ️** User report 2026-08-04 — reproduce by expanding; partial list; collapse + expand again fills out.
- **ℹ️** Related plan: **`docs/plans/done/0.14-DONE-tree-expand-save-restore.md`**
(`Connection.expanded`, `TreeListModel` `autoexpand = false`, bind on `GROUP` / `lxc_host`).
- **🔷** 2026-08-05 — user: have **not** seen it recently; keep the bug open.
- **✔️** 2026-08-14 — code walk of load vs expand apply.
- **✔️** 2026-08-14 — user reproduced; `~/.cache/rooterm/rooterm.debug.log` from that launch.

### Reproduce log (08:47:25–08:47:26)

- **✔️** `MainWindow.show_docked` at `08:47:26.007` (ListView maps / first bind).
- **✔️** Then **36** `Gtk-CRITICAL` in ~2ms (`08:47:26.013`–`.015`):
`gtk_widget_insert_after: assertion 'previous_sibling == NULL || _gtk_widget_get_parent (previous_sibling) == parent' failed`
- **✔️** Local PTY spawn starts later (`08:47:26.033`) — after the criticals, not the cause.
- **ℹ️** Same `gtk_widget_insert_after` when setting `TreeListRow.expanded` inside factory bind:
[GNOME Discourse 27037](https://discourse.gnome.org/t/columnview-with-treelistmodel-is-it-possible-to-autoexpand-model-at-only-top-level/27037).
- **ℹ️** Later `adw_tab_view_get_page` / `set_selected_page` criticals (`08:47:26.032`) — local-tab restore; not this tree bug.

### `connections.json` at reproduce (expand defaults `true` if omitted)

- **✔️** `all`: `GROUP`, `expanded=true`, **41 children** (hosts + nested group / LXC hosts).
- **✔️** `Localhost`: forced open on bind; 8 `LOCAL_PATH` children.
- **✔️** `mediaoutreach`: `GROUP`, `expanded=true`, 19 children.
- **✔️** Nested under `all`: `hebe 24hr` is `lxc-host` with 4 containers (`expanded` default true) — also expands during the same bind pass.

### How the nest is built (before UI)

- **✔️** `MainWindow` loads the nest **before** `new Host.Tree(this)`:
  - Ásbrú: `asbru.to_host_tree()` then `tree.config` / save.
  - Else: `this.tree = Host.TreeNodes.load(this.config)`.
- **✔️** `TreeNodes.from_json`:
  - Deserialize each `Connection` (includes `expanded`; default `true`).
  - `append(parent, conn)` builds the nest.
  - Recurse JSON `children` (deserialize leaves `Connection.children` empty).
- **✔️** Still before the widget: ensure Localhost / “All”, then `tree.sort(...)`.
- **✔️** The `Idle.add` in that stretch is `store_pending_secrets` only — **not** expand restore.

### How the widget attaches

- **✔️** `Host.Tree` wraps the live root list; it does not copy or rebuild the nest.
- **✔️** `Gtk.TreeListModel(window.tree, passthrough=false, autoexpand=false, create_func → conn.children)`.
- **✔️** With `autoexpand = false`, the flattened model starts as **root rows only**.
Children already exist on `Connection.children`; they join the flattened list only when a `Gtk.TreeListRow` expands.

### How expansion is applied today (not an idle pass)

- **✔️** No “walk the tree and restore expand” after realize.
- **✔️** Restore happens in `factory.bind` when ListView paints a visible row:
  - Localhost: always `list_row.expanded = true` (not persisted). 
  - `GROUP` / `lxc_host`: `bind_property("expanded", list_row, "expanded", SYNC_CREATE | BIDIRECTIONAL)`.
  - Other kinds: no expand restore.
- **✔️** `SYNC_CREATE` expands the `TreeListRow` **during bind** if `Connection.expanded` is true.
That calls `create_func`, then inserts children into the flattened model.
- **✔️** `factory.unbind` (ListView recycle) drops `expand_binding`; next bind recreates it.
- **✔️** Save is the other direction: `append` wires `notify["expanded"]` → `tree.save()` for groups / LXC hosts.

## Root cause

- **✔️** Restore writes `TreeListRow.expanded` **inside** `factory.bind` (`SYNC_CREATE` and Localhost force-open).
- **✔️** That mutates `TreeListModel` while ListView is inserting row widgets → `gtk_widget_insert_after` criticals → flattened/widget tree only partly filled.
- **✔️** Matches the reproduce: quit with `all` expanded (41 children) → reopen → first paint under-fills; collapse + expand is a normal TreeExpander toggle (model already known) and fills.
- **🚫** Do not “fix” with a defensive force-expand-twice / idle re-expand of the same row.

## Proposed fix

- **✔️** Apply saved expand on `TreeListModel` **before** `ListView` exists (no widgets yet). Loop flattened rows; `n_items` grows as parents expand so nested `GROUP` / `lxc_host` / Localhost restore in the same walk.
- **✔️** `factory.bind`: keep bidirectional bind for user toggle → save; **do not** write `expanded` during bind (drop Localhost force and `SYNC_CREATE`).
- **🚫** `Idle.add` to expand again after map (symptom workaround).
- **✅** After the user collapses a parent and re-expands: nested restore was a feared knock-on; user saw none.

### `src/Host/Tree.vala` — restore on the model, then stop expanding in bind

#### Add (after `TreeListModel` is created, before `SingleSelection` / `ListView`)

```vala
			for (var i = 0; i < this.tree_model.get_n_items(); i++) {
				var row = this.tree_model.get_item(i) as Gtk.TreeListRow;
				if (row == null) {
					continue;
				}
				var conn = row.item as Connection;
				if (conn == null) {
					continue;
				}
				if (conn.kind == ConnectionKind.LOCAL) {
					row.expanded = true;
					continue;
				}
				if (conn.kind != ConnectionKind.GROUP && !conn.lxc_host) {
					continue;
				}
				row.expanded = conn.expanded;
			}
```

#### Remove (from `factory.bind`)

```vala
				if (conn.kind == ConnectionKind.LOCAL) {
					list_row.expanded = true;
				} else if ((conn.kind == ConnectionKind.GROUP || conn.lxc_host)
					&& conn.expand_binding == null) {
					conn.expand_binding = conn.bind_property(
						"expanded",
						list_row,
						"expanded",
						GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL
					);
				}
```

#### Replace with

```vala
				if ((conn.kind == ConnectionKind.GROUP || conn.lxc_host)
					&& conn.expand_binding == null) {
					conn.expand_binding = conn.bind_property(
						"expanded",
						list_row,
						"expanded",
						GLib.BindingFlags.BIDIRECTIONAL
					);
				}
```

## Attempts / changelog

- **ℹ️** 2026-08-05 — still open; unreproduced recently per user.
- **ℹ️** 2026-08-14 — documented load vs bind timing in this log. No code edits.
- **✔️** 2026-08-14 — reproduce log: 36 `gtk_widget_insert_after` criticals at `show_docked`; `all` has 41 children expanded.
- **✔️** 2026-08-14 — applied proposed `Host.Tree` edit (model restore before `ListView`; bind is bidirectional only). Built.
- **✅** 2026-08-14 — user: no knock-ons seen; close out.

### Knock-ons watched (not seen)

- **✅** Nested `GROUP` / `lxc_host` after collapse/re-expand of a parent — user saw none.
- **✅** Bidirectional bind writing `expanded=false` back onto `Connection` — user saw none.
- **ℹ️** Localhost collapse lasts for the session; next launch still forces it open.
- **ℹ️** A group / LXC host added while running will not auto-expand (no `SYNC_CREATE`).

## Next

- **✅** 2026-08-14 — closed out; moved to `docs/bugs/done/`.

