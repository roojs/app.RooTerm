# Reconnect after SSH exit skips OpenSession login

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ fixed — Enter reconnect runs {@link Jobs.OpenSession} on the same tab

**Started:** 2026-07-30

---

## Problem

- **🔷** After an SSH child exits (accidental exit / disconnect), the tab shows the closing countdown (fair).
- **🔷** **Enter** should reconnect and run the same login flow as a new session (feed password / passphrase, optional sudo / lxc).
- **🔷** **Actual:** Enter reconnects but only re-spawns SSH; the password prompt is left for the user to type.

### Reproduction

1. Open a password-auth host (or any host that needs {@link OpenSession} login).
2. Let the remote shell exit (or kill the SSH child) so the tab is EXITED with the close bar.
3. Press **Enter** (reconnect).
4. **Expected:** password/passphrase fed; shell (and sudo/lxc if configured).
5. **Actual:** SSH password prompt waits for keyboard input.

---

## Evidence

- **ℹ️** First open: {@link MainWindow} / {@link SessionController.open_new} → `new OpenSession` → `run()` → `spawn` + `login`.
- **ℹ️** EXITED hint text tells the user **Enter to reconnect** (`SshTerminal` `child_exited`).
- **✔️** {@link SshTerminal.reconnect} only resets stream marks and calls `this.spawn()` — no job.
- **ℹ️** Already flagged as **💩** in `docs/plans/done/0.5-DONE-dialog-terminal-workflows.md` (dead-tab reconnect still only `spawn()`).
- **🚫** Not a feature gap for “delete connection closes sessions” (`docs/plans/done/0.6-DONE-…`) — wrong place for this fix.

---

## Root cause

- **✔️** Reconnect path never constructs {@link OpenSession} (or any {@link Job}) on the **existing** tab. {@link Job} always `sessions.create`s a **new** tab, so there was no adopt path; `reconnect()` took the shortcut of bare `spawn()`.

---

## Proposed fix

- **🔷** Enter reconnect must run {@link OpenSession} on the **same** EXITED tab (login / sudo / lxc).
- **💩** Optional `Terminal? existing` on {@link Job} / {@link SshLogin} / {@link SudoLogin} / {@link OpenSession} ctors: when set, adopt instead of `sessions.create`.
- **💩** {@link SshTerminal.reconnect}: cancel close bar, reset stream, `new OpenSession(window, connection, this)` + `run.begin` (`run` still `spawn`s then `login`). Window from `get_root() as MainWindow`; if null, keep bare `spawn()` as last resort.
- **🚫** New helper methods for reconnect.
- **🚫** Opening a second tab to “reconnect.”

### 1. `src/Jobs/Job.vala` — optional existing terminal

**Why:** Reuse EXITED tab; `create` always adds a new one.

**Where:** `Job` constructor signature and first lines after `Object(...)`.

**Depends on:** none.

#### Remove
```vala
		protected Job(MainWindow window, Connection connection)
		{
			Object(window: window, connection: connection);
			this.terminal = this.window.sessions.create(this.connection);
			var ssh = this.terminal as SshTerminal;
```

#### Replace with
```vala
		protected Job(MainWindow window, Connection connection, Terminal? existing = null)
		{
			Object(window: window, connection: connection);
			if (existing != null) {
				this.terminal = existing;
			} else {
				this.terminal = this.window.sessions.create(this.connection);
			}
			var ssh = this.terminal as SshTerminal;
```

### 2. `src/Jobs/SshLogin.vala` — pass `existing` through

**Where:** `SshLogin` constructor.

**Depends on:** §1.

#### Remove
```vala
		public SshLogin(MainWindow window, Connection connection)
		{
			base(window, connection);
		}
```

#### Replace with
```vala
		public SshLogin(MainWindow window, Connection connection, Terminal? existing = null)
		{
			base(window, connection, existing);
		}
```

### 3. `src/Jobs/SudoLogin.vala` — pass `existing` through

**Where:** `SudoLogin` constructor.

**Depends on:** §2.

#### Remove
```vala
		public SudoLogin(MainWindow window, Connection connection)
		{
			base(window, connection);
		}
```

#### Replace with
```vala
		public SudoLogin(MainWindow window, Connection connection, Terminal? existing = null)
		{
			base(window, connection, existing);
		}
```

### 4. `src/Jobs/OpenSession.vala` — accept existing tab

**Where:** `OpenSession` constructor.

**Depends on:** §3.

#### Remove
```vala
		public OpenSession(MainWindow window, Connection connection)
		{
			base(window, connection);
			var ssh = (SshTerminal) this.terminal;
			ssh.exited.connect(() => {
				if (ssh.selected) {
					ssh.close_in(30);
				}
			});
		}
```

#### Replace with

Adopt optional existing tab. Focused `close_in(30)` on EXITED belongs on {@link SshTerminal} `child_exited` (see plan **0.6** §2) — do not re-attach here if that plan lands first; if applying this bug alone, keep the `exited` handler until 0.6 §2.

```vala
		public OpenSession(MainWindow window, Connection connection, Terminal? existing = null)
		{
			base(window, connection, existing);
			var ssh = (SshTerminal) this.terminal;
			ssh.exited.connect(() => {
				if (ssh.selected) {
					ssh.close_in(30);
				}
			});
		}
```

### 5. `src/SshTerminal.vala` — `reconnect()` starts OpenSession

**Where:** `reconnect()` method.

**Depends on:** §4.

#### Remove
```vala
		public void reconnect()
		{
			if (this.state != SessionState.EXITED) {
				return;
			}
			this.cancel_close();
			this.stream.hide_input = false;
			this.stream.log_line = -1;
			this.stream.prompt_hint = "";
			this.state = SessionState.IDLE;
			this.spawn();
		}
```

#### Replace with
```vala
		public void reconnect()
		{
			if (this.state != SessionState.EXITED) {
				return;
			}
			this.cancel_close();
			this.stream.hide_input = false;
			this.stream.log_line = -1;
			this.stream.prompt_hint = "";
			this.state = SessionState.IDLE;
			var window = this.get_root() as MainWindow;
			if (window == null) {
				this.spawn();
				return;
			}
			var job = new OpenSession(window, this.connection, this);
			job.run.begin((obj, res) => {
				try {
					job.run.end(res);
				} catch (JobError e) {
					GLib.warning("reconnect failed name=%s: %s", this.connection.name, e.message);
				}
			});
		}
```

---

## Next

- **✅** Manual verify: exit SSH → Enter → password fed / shell without typing.

---

## Attempts / changelog

- **ℹ️** 2026-07-30: Diagnosis from code review (user report). No code applied yet.
- **ℹ️** Briefly drafted as plan **0.6** §4 — moved here; stripped from that plan.
- **✔️** 2026-08-01: Applied proposed fix — `Job`/`SshLogin`/`SudoLogin`/`OpenSession` optional `existing`; `Ssh.reconnect` runs `OpenSession` on the same tab.
- **✅** 2026-08-01: User verified reconnect login flow; moved to `docs/bugs/done/`.
