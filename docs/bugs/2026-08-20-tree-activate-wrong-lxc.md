# Tree double-click opens wrong LXC / host

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ✔️ fix applied — awaiting user verify

**Started:** 2026-08-20

---

## Problem

- **🔷** On host **SGFS one**, double-click the **host** row → opens a **container** terminal instead of a plain host SSH session.
- **🔷** Double-click / open a **different** container (e.g. **web-release-64**) → opens the **same** container as before, not the one selected.
- **🔷** Expected: activate the **clicked** row (`Connection` at that tree position).
- **🔷** Select (single-click) a host that is **not active** (no sessions on that row) → **do nothing** (do not jump to an open child tab).

## Evidence

- **ℹ️** Activate path: `Host.Tree` `list_view.activate` → `connection_activated` → `MainWindow` → `Jobs.OpenSession(conn)`.
- **ℹ️** Highlight path: `notify["selected"]` → `connection_highlighted` → may show page + `sessions.focus()` → `display_changed` → `host_tree.select(page.current.connection)`.
- **ℹ️** Closed LXC / local-path already early-return in `connection_highlighted` when `sessions == 0` (0.19). **Host** with `sessions == 0` still continues.
- **✔️** 2026-08-20 22:46 — user reproduce with `--debug`.

### Reproduce log (22:46)

- **✔️** First activate (container) — OK: before=after `web-release64`.
- **✔️** Second activate (host) — wrong:
  - `before name=mediaoutreach - sgfs1` (`open=0 children_open=1`)
  - `after name=web-release64`
  - `open_session name=web-release64`

## Root cause

- **✔️** Click / activate selects the **host** (no sessions on the host row).
- **✔️** `connection_highlighted` still runs for inactive **HOST** (unlike LXC / path): shows the host page and `focus()`.
- **✔️** `display_changed` then `host_tree.select(page.current.connection)` — that is the **already-open container** tab.
- **✔️** Tree selection jumps to the container; activate then opens that container again.
- **🚫** Not primarily a search/refilter index race (`search=` / `show_all=0` already on the bad activate).

## Proposed fix (✔️ applied)

#### Remove — `src/MainWindow.vala` highlight: host with no sessions still switches page

```vala
			this.host_tree.connection_highlighted.connect((conn) => {
				if (conn.sessions.get_n_items() == 0) {
					switch (conn.kind) {
						case Host.ConnectionKind.LOCAL_PATH:
						case Host.ConnectionKind.LXC:
							return;

						default:
							break;
					}
				}
```

#### Replace with — any row with no sessions: select does nothing

```vala
			this.host_tree.connection_highlighted.connect((conn) => {
				if (conn.sessions.get_n_items() == 0) {
					return;
				}
```

#### Remove — `src/Host/Tree.vala` temporary activate debug

Restore activate without the before/after `GLib.debug` block (selection-then-read is fine once highlight no longer steals).

#### Remove — `src/Jobs/OpenSession.vala` temporary `open_session` debug

```vala
			GLib.debug(
				"open_session name=%s kind=%d lxc=%s sudo=%d",
				this.connection.name,
				(int) this.connection.kind,
				this.connection.lxc_name,
				(int) this.connection.sudo_after_login
			);
			if (this.connection.lxc_name.length > 0) {
```

#### Replace with

```vala
			if (this.connection.lxc_name.length > 0) {
```

## Attempts / changelog

- **✔️** 2026-08-20 — bug log; debug in `Tree` activate + `OpenSession.run`.
- **✔️** 2026-08-20 — user reproduce; before≠after on host double-click.
- **✔️** 2026-08-20 — revised: inactive host highlight → `select(page.current)` steals selection to open container.

## Attempts / changelog (cont.)

- **✔️** 2026-08-20 — applied: inactive row highlight returns early; stripped activate / open_session debug.
- **✔️** 2026-08-20 — select open row must focus VTE: `sessions.focus()` grabs the terminal; `Tree.select` scrolls without `FOCUS` so the tree does not steal the keyboard back.

## Next

- **⏳** 🔷 Re-test: single-click inactive host (no jump); single-click open row then Enter goes to shell; double-click host opens host SSH; double-click second container opens that one.
- **⏳** 🔷 On verify: rename to `FIXED` and move to `docs/bugs/done/`.
