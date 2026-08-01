# Cosmetic + SSH options: tab label, scrollbar, tree sync, icons, ipqos

> Pointer: `docs/bug-fix-process.md` (emoji).

**Status:** ✔️ code applied — await user verify

**Started:** 2026-08-01

---

## Tracking index

| # | Topic | Status |
| - | ----- | ------ |
| A | SSH tab label includes hostname | ✔️ |
| B | Close-countdown bar transparent gap | ✔️ (re-diagnosed) |
| C | Tree highlight not syncing on close / tab | ✔️ |
| D | Local terminal child icon wrong | ✔️ |
| E | Session-mark buttons inflate tree row height | ✔️ |
| F | `ipqos=cs0` SSH spawn error | ✔️ |

---

## A — SSH tab label

### Problem

- **🔷** Bottom tab for SSH should **not** start with the hostname; show path/prompt detail only.

### Root cause

- **✔️** `Terminal.Ssh.label()` returns `connection.name + "  " + detail`.

### Fix

- **🔷** `label()` → detail only (fallback name); tooltip keeps host + detail.

---

## B — Close-countdown bar gap

### Problem

- **🔷** Closing-session countdown strip shows a transparent gap top and bottom (not a tab scrollbar).

### Root cause

- **✔️** `close_bar` had outer margins on a transparent VTE parent (`.vte-path` / host page), so desktop showed through around the strip.
- **🚫** TabBar overlay scrolling was the wrong diagnosis (reverted).

### Fix

- **🔷** Drop close_bar margins; use padding inside `.close-bar` with opaque `@window_bg_color`.

---

## C — Tree selection sync

### Problem

- **🔷** Closing a host and shifting to another (or activating a bottom tab) does not update the left-tree highlight.

### Root cause

- **✔️** `Session.Controller.focus` / `display_changed` update the window title only; nothing calls `host_tree.select` for the focused terminal’s connection.

### Fix

- **🔷** On `display_changed`, select `page.current.connection` in the tree.

---

## D — Local terminal icon

### Problem

- **🔷** Local path rows should use the old Localhost icon (`computer`); Localhost itself stays a folder.

### Root cause

- **✔️** After making LOCAL=`folder`, LOCAL_PATH was set to `utilities-terminal` instead of the prior LOCAL icon `computer`.

### Fix

- **🔷** LOCAL_PATH → `computer`.

---

## E — Session mark button height

### Problem

- **🔷** Multiple SSH session buttons make the host row taller than other rows.
- **🔷** Want **smaller buttons** (chrome), not smaller icons.

### Fix

- **🔷** `button.session-icon` min size 0 / padding 0; icons stay `pixel_size` 16.

---

## F — `ipqos=cs0` error

### Problem

- **🔷** Connecting `roojs - ai` shows: `command-line line 0: no argument after keyword "ipqos=cs0"`.

### Evidence

- **✔️** options: `-x -o "IPQoS=cs0" -o "ServerAliveCountMax=3" -o "ServerAliveInterval=60"`
- **✔️** `split_set(" \t")` keeps literal quotes → ssh `-o` sees keyword `ipqos=cs0` with no value.

### Fix

- **🔷** Parse options with `GLib.Shell.parse_argv` (quote-aware, strips quotes).

### Editability

- **✔️** `Dialog.Connection` has **no** Options field — Ásbrú `options` are stored/used but invisible in the UI.
- **💩** Add a plain “SSH options” entry on the connection dialog (load/save `connection.options`).

---

## Attempts / changelog

- **ℹ️** 2026-08-01 — user voice dump of A–F; this log created; fixes applied in same pass.
- **✔️** A: `Ssh.label` path-only; `Page.tab_tooltip` keeps host for hover.
- **🚫** B first pass: TabBar overlay scrolling (wrong) — reverted.
- **✔️** B: close_bar margins → inner padding on opaque `.close-bar`.
- **✔️** C: `MainWindow` `display_changed` → `host_tree.select(page.current.connection)`.
- **✔️** D: `LOCAL_PATH` icon → `computer` (LOCAL stays `folder`).
- **✔️** E: button chrome min 0; icons stay 16px (not shrunk icons).
- **✔️** F: `GLib.Shell.parse_argv` for connection options (strips Ásbrú quotes).
- **⏳** F follow-up: options field in Edit Connection — propose / await approve.
