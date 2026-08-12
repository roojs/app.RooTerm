# Duplicate Localhost / LOCAL_PATH rows grow on every startup

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed out 2026-08-05

**Started:** 2026-08-04

---

## Problem

- **🔷** Startup restore of local tabs creates **more** tree rows every launch (paths under Localhost double; feels like “more Localhosts”).
- **🔷** Path / local-shell session rows are saved under Localhost in `connections.json`.
- **🔷** After save + relaunch, old `LOCAL_PATH` rows remain and **new** ones are appended for the same cwds.
- **🔷** New local tabs attach to `MainWindow.localhost`; orphan path children stay under leftover Localhost roots.

### Reproduction

1. Run RooTerm with open local shells so `LOCAL_PATH` children are saved under Localhost.
2. Quit and start again (repeat).
3. **Expected:** one Localhost; same path tabs restored (no extras).
4. **Actual:** path children multiply each launch; may already have **two** Localhost roots from the earlier bug.

### Live evidence (`~/.config/rooterm/connections.json`, 2026-08-04)

- **✔️** Two root `LOCAL` nodes, both `uuid = "localhost"`.
- **✔️** Many `LOCAL_PATH` children for only two distinct cwds (grew across launches).

---

## Evidence

- **✔️** Earlier: `MainWindow` always invented Localhost → two roots when one was already loaded. Guard applied (`!by_uuid.has_key("localhost")`).
- **✔️** That guard **stops new Localhost roots**; it does **not** stop path growth.
- **✔️** `TreeNodes.append` / `by_uuid.set` — duplicate `uuid = "localhost"` overwrites the map while **both** roots stay in the nest.
- **✔️** Startup restore only `by_uuid.unset` then `open_local(localhost, cwd)` invents new nest rows; `save` keeps old + new.
- **ℹ️** 0.13 assumed load left `LOCAL_PATH` in `by_uuid` only (no nest). After tree-owned connections, `TreeNodes.from_json` nests them under Localhost.
- **ℹ️** Related: `docs/plans/done/0.13-DONE-auto-restore-local-tabs.md`, `docs/bugs/done/2026-08-01-FIXED-tab-password-localhost-tree.md`.

---

## Root cause

- **✔️** Restore only drops `LOCAL_PATH` from `by_uuid`, then re-opens via `open_local`, which **appends new** nest children; save persists both → exponential path duplicates.
- **✔️** Pre-existing second Localhost root is leftover from the earlier missing-guard bug (guard alone does not merge/remove it).

---

## Proposed fix

- **🔷** **Load:** duplicate uuid → skip that object entirely (no append, no children).
- **🔷** **`open_local`:** page owner is Localhost (or `connection.parent` when restoring a path); `by_uuid.get` then create if null; terminal keeps `connection` so `Page.add` can tell invent vs restore.
- **🔷** **`Page.add`:** `switch (term.connection.kind)` — `LOCAL_PATH` append; `LOCAL` invent; default append to page connection.
- **🔷** **Startup:** one reverse walk of `this.localhost.children` — missing cwd `tree.remove`, else `open_local(conn)`.
- **🔷** User closes extras → safe. **No** automatic ghost wipe.
- **🚫** Collect/find/second-pass loops; `Page.restore` / `wire_tab`; trivial aliases; explicit types on locals; `children[i]` (use `.get`).

### `src/Host/TreeNodes.vala` — `from_json` skip duplicate uuid, keep children

#### Remove
```vala
				var conn = Json.gobject_deserialize(typeof(Connection), element) as Connection;
				if (conn == null) {
					continue;
				}
				root.append(parent, conn);
				TreeNodes.from_json(children_node, root, conn);
```

#### Replace with
```vala
				var conn = Json.gobject_deserialize(typeof(Connection), element) as Connection;
				if (conn == null) {
					continue;
				}
				if (conn.uuid.length > 0 && root.by_uuid.has_key(conn.uuid)) {
					GLib.debug("skip duplicate uuid=%s name=%s", conn.uuid, conn.name);
					continue;
				}
				root.append(parent, conn);
				TreeNodes.from_json(children_node, root, conn);
```

### `src/Session/Controller.vala` — `open_local` handles path rows

#### Remove
```vala
		/**
		 * Open a local shell tab under Localhost (creates host page if needed).
		 *
		 * @param connection Localhost connection
		 * @param cwd Working directory (home when empty)
		 * @return The new local terminal
		 */
		public Terminal.Local open_local(Host.Connection connection, string cwd = "")
		{
			Host.Page page;
			if (this.by_uuid.has_key(connection.uuid)) {
				page = this.by_uuid.get(connection.uuid);
			} else {
				page = new Host.Page(connection, this.tree, this.config);
				page.empty.connect(() => {
					this.close(page);
				});
				page.changed.connect(() => {
					this.focus();
				});
				this.by_uuid.set(connection.uuid, page);
				this.stack.pages.add_named(page, connection.uuid);
			}

			var term = new Terminal.Local(connection, this.terminal_font, this.config, cwd);
```

#### Replace with
```vala
		/**
		 * Open a local shell tab under Localhost (creates host page if needed).
		 * Pass Localhost for a new tab, or an existing {@link Host.ConnectionKind.LOCAL_PATH}
		 * to reopen that row without inventing another.
		 *
		 * @param connection Localhost, or a Localhost path child to restore
		 * @param cwd Working directory (home when empty; path row uses {@link Host.Connection.cwd})
		 * @return The new local terminal
		 */
		public Terminal.Local open_local(Host.Connection connection, string cwd = "")
		{
			if (connection.kind == Host.ConnectionKind.LOCAL_PATH && cwd.length == 0) {
				cwd = connection.cwd;
			}
			// Host.Page is always the Localhost row (parent when restoring a path).
			var page_connection = connection.kind == Host.ConnectionKind.LOCAL_PATH
				? connection.parent : connection;
			var page = this.by_uuid.get(page_connection.uuid);
			if (page == null) {
				page = new Host.Page(page_connection, this.tree, this.config);
				page.empty.connect(() => {
					this.close(page);
				});
				page.changed.connect(() => {
					this.focus();
				});
				this.by_uuid.set(page_connection.uuid, page);
				this.stack.pages.add_named(page, page_connection.uuid);
			}

			var term = new Terminal.Local(connection, this.terminal_font, this.config, cwd);
```

**ℹ️** `var` locals. Map miss → null is Gee’s contract. `page_connection` picks the Localhost row for the page. `Page.add` uses `switch` on kind.

### `src/Host/Page.vala` — `add` invent only when terminal is still Localhost

#### Remove
```vala
			if (this.connection.kind == ConnectionKind.LOCAL) {
				var row = new Connection() {
					uuid = GLib.Uuid.string_random(),
					name = term.label(),
					cwd = term.cwd.length > 0 ? term.cwd : GLib.Environment.get_home_dir(),
					kind = ConnectionKind.LOCAL_PATH,
					parent_uuid = this.connection.uuid
				};
				term.connection = row;
				row.sessions.append(term);
				this.tree.append(this.connection, row);
				this.tree.save();
			} else {
				this.connection.sessions.append(term);
			}
			return tab;
```

#### Replace with
```vala
			switch (term.connection.kind) {
				case ConnectionKind.LOCAL_PATH:
					term.connection.sessions.append(term);
					break;

				case ConnectionKind.LOCAL:
					var row = new Connection() {
						uuid = GLib.Uuid.string_random(),
						name = term.label(),
						cwd = term.cwd.length > 0 ? term.cwd : GLib.Environment.get_home_dir(),
						kind = ConnectionKind.LOCAL_PATH,
						parent_uuid = this.connection.uuid
					};
					term.connection = row;
					row.sessions.append(term);
					this.tree.append(this.connection, row);
					this.tree.save();
					break;

				default:
					this.connection.sessions.append(term);
					break;
			}
			return tab;
```

### `src/MainWindow.vala` — one reverse walk of Localhost children

#### Remove
```vala
			var restore = new Gee.ArrayList<Host.Connection>();
			foreach (var conn in this.tree.by_uuid.values) {
				if (conn.kind != Host.ConnectionKind.LOCAL_PATH) {
					continue;
				}
				restore.add(conn);
			}
			Terminal.Local? term = null;
			foreach (var conn in restore) {
				this.tree.by_uuid.unset(conn.uuid);
				if (!GLib.FileUtils.test(conn.cwd, GLib.FileTest.IS_DIR)) {
					continue;
				}
				term = this.sessions.open_local(this.localhost, conn.cwd);
			}
			if (term == null) {
				term = this.sessions.open_local(this.localhost);
			}
			this.tree.save();
```

#### Replace with
```vala
			var term = (Terminal.Local?) null;
			for (var i = this.localhost.children.size - 1; i >= 0; i--) {
				var conn = this.localhost.children.get(i);
				if (conn.kind != Host.ConnectionKind.LOCAL_PATH) {
					continue;
				}
				if (!GLib.FileUtils.test(conn.cwd, GLib.FileTest.IS_DIR)) {
					this.tree.remove(conn);
					continue;
				}
				term = this.sessions.open_local(conn);
			}
			if (term == null) {
				term = this.sessions.open_local(this.localhost);
			}
			this.tree.save();
```

**ℹ️** Reverse index so `remove` is safe in the same pass. `.get(i)` not `[]`.

---

## Attempts / changelog

- **🚫** 2026-08-04 — merge/dedupe; prune-list + by_uuid scan; `restore_local` / `Page.restore` / `wire_tab`.
- **✔️** 2026-08-04 — root cause: restore `unset` + `open_local` invent leaves nest ghosts.
- **🔷** 2026-08-04 — duplicate uuid → plain `continue` (ignore object + children; no reparent).
- **🔷** 2026-08-04 — extend `open_local` + `Page.add` by kind; one reverse walk of `localhost.children`.
- **🔷** 2026-08-04 — coding-standards pass: `var` locals; `get`+null; `switch` on kind; `.get(i)`.
- **✔️** 2026-08-04 — applied visible fences: `TreeNodes.from_json`, `open_local`, `Page.add`, MainWindow restore walk.
- **💩** 2026-08-04 — proposal slimmed to that.

- **✅** 2026-08-05 — user: clean up fixed bugs → `done/`.

## Next

- **✅** 2026-08-05 — closed out; moved to `docs/bugs/done/`.
