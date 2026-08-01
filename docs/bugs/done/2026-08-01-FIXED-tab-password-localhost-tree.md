# FIXED — tab width, password feed, localhost tree

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user verified 2026-08-01

**Started:** 2026-08-01

**Related (separate, mostly done):**

- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-toggle-key-tooltip-and-binding.md` — tooltip kebab-case + steal F1 from Guake
- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-docked-ui-not-under-panel.md` — D-Bus name race / dock retry

---

## Tracking index

| # | Topic | Status |
| - | ----- | ------ |
| A | Adw tab button width | ✅ `Host.TabBar` + max 30% / equal-share shrink |
| B | Password / userpass auto-feed fails | ✅ schema unified |
| C | Localhost tree: selection + icons + session marks | ✅ icons/sessions/select |

---

## A — Tab button width

### Problem

- **🔷** Tab buttons on the bottom strip are too narrow; user asked ~50% wider earlier.
- **🔷** Earlier CSS `max-width` was removed (invalid for that node); `min-width: 240px` was tried — still not satisfactory / may not apply.

### Evidence

- **✔️** Official Adw docs: only documented width control is [`Adw.TabBar:expand-tabs`](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1-latest/property.TabBar.expand-tabs.html)
  - `TRUE` → tabs fill / share full bar width
  - `FALSE` → “minimum possible size” (current: `expand_tabs = false` in `Host/Page.vala`)
- **✔️** No documented per-tab min/max width API; CSS node documented as `tabbar` only
- **ℹ️** Current CSS: `resources/style.css` `tabbar.thin-tabbar tab` / `tabbox > tab` **`min-width: 360px`** (bumped from 240; broader selector). Restart app to reload gresource CSS.

### Root cause

- **✔️** Wanted “medium” width is outside Adw’s documented contract.

### Fix applied

- **🔷** Dropped `Adw.TabBar`; added `Host.TabBar` bound to the same `Adw.TabView`.
- **🔷** Select / close / title / tooltip / `+` (`win.new-terminal`) wired in the bar ctor.
- **🔷** Fixed tab width: `width_request = 280`, no `hexpand`; strip scrolls when crowded; max 30% / equal-share shrink.

---

## B — Password authentication auto-feed broken

### Problem

- **🔷** Hosts with plain **password / userpass** auth: automatic password feed fails (e.g. “Heebee Haven 24 Hour”).
- **🔷** Typing the password manually in the VTE works.
- **🔷** User: reproduces on more than one password host — “we seem to have broken password authentication, plain.”

### Reproduction

1. Open a connection with `auth` = userpass / password (secret in keyring).
2. Expect: job detects password prompt and `feed_child` password + newline.
3. Actual: prompt sits waiting; manual type succeeds.

### Evidence

- **✔️** 2026-08-01 ~16:28 — `hebe 24hr` open with `--debug` (`~/.cache/rooterm/rooterm.debug.log`):

```
Ssh.vala:200: spawn secret uuid=04bc8f19-… pass_len=0 name=hebe 24hr
Job.vala:200: job expect … want=5 (WAIT_SSH_PASSWORD)
SshLogin.vala:125: current_state 0 -> 5 want=5
OpenSession.vala:71: login feed password … pass_len=0 auth=userpass
Job.vala:200: job expect … want=6 (WAIT_SHELL_PROMPT)
SshLogin.vala:125: current_state 0 -> 5 want=6   ← still at password prompt
MainWindow.vala:201: open session failed … login shell timeout
```

- **✔️** Also immediately before lookup: `GTask secret_service_async_initable_init_async … finalized without ever returning` (libsecret / Secret Service flake or race)
- **✔️** Prompt detection **worked** (state → WAIT_SSH_PASSWORD). Feed ran. Password string was **empty**.
- **✔️** Manual type works because the keyring is bypassed.

### Root cause

- **✔️** `Secret.password_lookup_sync` for uuid `04bc8f19-…` returned empty → `pass_len=0` → fed `"\n"` only → SSH stayed at password prompt → shell expect timed out.
- **✔️** **Schema name mismatch** (code):
  - Dialog load/save: `org.roojs.rooterm.Connection` (`Dialog/Connection.vala`)
  - Spawn lookup: `org.roojs.rooterm.Host.Connection` (`Terminal/Ssh.vala`)
  - Ásbrú pending store: `org.roojs.rooterm.Host.Connection` (`Config.vala`)
- **✔️** User: Edit Connection dialog shows the password correctly → secret exists under the **dialog** schema; spawn looks under the **other** name → empty.
- **ℹ️** GTask Secret Service warning may be noise; empty lookup is explained by the schema mismatch.

### Fix applied

Unify on the schema the dialog already uses (where live secrets are), so spawn finds them.

**Where:** `src/Terminal/Ssh.vala` password lookup; `src/Config.vala` `store_pending_secrets` (same string for Ásbrú imports).

#### Remove (`Ssh.vala` and matching `Config.vala` store schema)
```vala
							"org.roojs.rooterm.Host.Connection", Secret.SchemaFlags.NONE,
```

#### Replace with
```vala
							"org.roojs.rooterm.Connection", Secret.SchemaFlags.NONE,
```

- **🔷** One string everywhere for host passwords: `org.roojs.rooterm.Connection`.
- **🚫** Do not only “skip feed when empty”.
- **ℹ️** Old Ásbrú imports stored under `Host.Connection` (if any) would need a one-time re-save or dual lookup — optional follow-up; dialog-saved passwords are the broken path.

---

## C — Localhost tree: selection, icons, session marks

### Problem

On startup there is a Localhost terminal:

- **🔷** Tree shows **Localhost** (parent) **and** a **child** row for the actual terminal (`LOCAL_PATH`).
- **🔷** **Selection:** Localhost parent is selected; the **child** (the real terminal row) should be selected.
- **🔷** **Icons:** Localhost should look like a **folder**; the terminal child should look like a **terminal**.
- **🔷** **Session mark column:** Localhost parent currently has a right-hand terminal icon mark — **it should not**, because the child row already represents that session. Marks belong on the terminal row (or SSH hosts), not on the Localhost folder row when children exist.

### Reproduction

1. Start RooTerm (auto local terminal).
2. Look at left tree: Localhost expanded with a path child.
3. Note which row is highlighted and which icons appear on parent vs child.

### Evidence

- **ℹ️** `Host/Tree.vala` — session marks via `append_session_mark` on connection’s `sessions`; row icons TBD in factory
- **ℹ️** `Host/Page.vala` — local tabs create `LOCAL_PATH` children under Localhost
- **ℹ️** `Tree.select(connection)` — who calls it on open / `wire`?
- **✔️** Confirm which `Connection` is passed to `select` on first local open (parent vs path child)

### Root cause

- **🔷** Icons: `tree_icon` had LOCAL=`computer`, LOCAL_PATH=`folder` (swapped vs intent).
- **🔷** Marks: `Page.add` appended the local terminal to **Localhost**.`sessions` *and* the `LOCAL_PATH` child — parent got a mark.
- **🔷** Selection: startup `open_local` never called `host_tree.select` on the new `LOCAL_PATH` row (parent stayed highlighted).

### Fix applied

- **🔷** `Connection.tree_icon`: LOCAL → `folder`; LOCAL_PATH → `computer` (prior LOCAL icon; see later cosmetic bug log).
- **🔷** `Page.add`: local tabs only put the terminal on the `LOCAL_PATH` row’s `sessions` (not Localhost). Close path updated to match.
- **🔷** `MainWindow` after first `open_local`: Idle `host_tree.select(term.connection)` (the path child).

---

## Attempts / changelog

- **ℹ️** 2026-08-01 — user reported A/B/C in chat after F1/dock work; this file created so they are tracked.
- **🔷** 2026-08-01 — B: Secret schema unify `org.roojs.rooterm.Connection` (user: done).
- **🔷** 2026-08-01 — C: icons / sessions ownership / startup select applied.
- **🔷** A: max 30% / equal-share shrink on `Host.TabBar`.
- **✅** 2026-08-01 — user: fixed; moved to `docs/bugs/done/`.
