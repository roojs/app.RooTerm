# Batch on a host does not become root

> Pointer: `docs/bug-fix-process.md` (emoji).
> Related: `docs/bugs/done/2026-11-18-FIXED-script-run-as-root.md`.
> Related: `docs/plans/done/0.23-DONE-script-sender.md`.

**Status:** closed for 0.1.5. Not verified on a machine.

**Started:** 2026-11-18

---

## Problem

- **🔷** A batch run against a host (not an LXC container) stayed as the logged-in user.
- **🔷** It did not upgrade to root before the script body was sent.
- **🔷** The same kind of run against a container does land as root, because `lxc-attach` starts a root shell inside the container.
- **🔷** Expected: a host batch that should run as root runs `sudo -i` and waits for the root prompt, then sends the body.
- **🔷** Whether this batch should run as root is the script tick in `docs/bugs/done/2026-11-18-FIXED-script-run-as-root.md`. It is not the connection’s “sudo -i after login” tick.

## Evidence

- **ℹ️** `Jobs.Batch.run` logs in, then calls `sudo()` only when `connection.sudo_after_login` is set. `src/Jobs/Batch.vala`.
- **✔️** `Tab.Script.Run.append_job` assigns `job.script` before `job.run.begin`. The script is already on the job when `run()` decides whether to elevate. `src/Tab/Script/Run.vala`.
- **✔️** `SQT.Script` has no run-as column. `src/SQT/Script.vala`. `task.run_as` is unused by Edit Command.
- **ℹ️** `inject` sends `lxc-attach` only when `connection.kind` is `LXC`. A host skips that and feeds `script.body` at the shell `run()` left behind. `inject` never calls `sudo()`.
- **ℹ️** `Jobs.SudoLogin.sudo` is `sudo -i`, then the sudo password, then `WAIT_ROOT_PROMPT`. A host batch never reaches it unless that connection tick is on.
- **ℹ️** Interactive Open uses the same connection tick (`Jobs.OpenSession`). That path was not the test.

## Root cause

- **✔️** Elevation for a batch follows the connection, and a script has no run-as flag. A host whose connection tick is off stays the login user. A container still looks like root because `lxc-attach` starts a root shell on its own.

## Proposed fix

- **🔷** After the script tick exists, a host batch whose script is ticked run-as-root calls the existing `sudo()` before `inject`. A host whose script is not ticked stays the login user.
- **✔️** Property the tick writes: `SQT.Script.run_as_root` (`bool`, default false). Edit Command shows **Run as root** and Save / Run/Test store it after `pkexec`. See `docs/bugs/done/2026-11-18-FIXED-script-run-as-root.md`.
- **✔️** An LXC batch calls `sudo()` when `connection.sudo_after_login` is set, then `lxc-attach`. Attach does not sudo on the host. It starts a root shell inside the container, so a container stays available for a root script.
- **✔️** A host with `sudo_after_login` off cannot become root. On a root script the planning row stays unticked, the box cannot be turned on, and the name reads `name (no root)`. Select all skips it.
- **🚫** Treating “sudo -i after login” on the connection as the decision for a host batch.
- **🚫** A second sudo implementation beside `Jobs.SudoLogin.sudo`.

### `src/Jobs/Batch.vala` — `run()`: host elevation follows the script

**Why:** A host batch becomes root only when that script is ticked. The connection tick stays the interactive Open decision, and the LXC batch decision, until the container question is closed.

**Where:** `Jobs.Batch.run`, the block after `yield this.login()`.

**Depends on:** `SQT.Script.run_as_root` from `docs/bugs/done/2026-11-18-FIXED-script-run-as-root.md`.

#### Remove

```vala
			if (this.connection.sudo_after_login) {
				yield this.sudo();
			}
```

#### Replace with

```vala
			if (this.connection.kind == Host.ConnectionKind.LXC) {
				if (this.connection.sudo_after_login) {
					yield this.sudo();
				}
			} else if (this.script.run_as_root) {
				yield this.sudo();
			}
```

## Attempts / changelog

- **ℹ️** 2026-11-18 — logged from a host batch that did not become root. No code change.
- **ℹ️** 2026-11-18 — re-read `Jobs.Batch.run`, `Jobs.SudoLogin.sudo`, `SQT.Script`, and `Tab.Script.Run.append_job`. Root cause matches the code.
- **✔️** 2026-11-18 — applied the host hunk. `SQT.Script.run_as_root`, Edit Command tick, and `Jobs.Batch.run` (host uses the tick; LXC sudos on the host when that connection asks, then attach).
- **✔️** 2026-11-18 — planning hides root execution on a host with no sudo path: unticked, insensitive, label `name (no root)`.
- **✔️** 2026-11-18 — an LXC row without sudo after login does not log in. The terminal prints `no root on this host, cannot lxc-attach` and the job fails. The same row stays unticked in planning. Batch terminals use the preference font at scale 1.

## Next

- **✔️** Closed for 0.1.5 without a host run. Confirm later: tick **Run as root**, run the batch, and see `sudo -i` then a root prompt before the body.
