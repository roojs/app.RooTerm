# Batch on a host does not become root

> Pointer: `docs/bug-fix-process.md` (emoji).
> Related: `docs/bugs/2026-11-18-script-run-as-root.md`.
> Related: `docs/plans/done/0.23-DONE-script-sender.md`.

**Status:** ⏳ logged from a host batch. No code change.

**Started:** 2026-11-18

---

## Problem

- **🔷** A batch run against a host (not an LXC container) stayed as the logged-in user.
- **🔷** It did not upgrade to root before the script body was sent.
- **🔷** The same kind of run against a container does land as root, because `lxc-attach` starts a root shell inside the container.
- **🔷** Expected: a host batch that should run as root runs `sudo -i` and waits for the root prompt, then sends the body.
- **🔷** Whether this batch should run as root is the script tick in `docs/bugs/2026-11-18-script-run-as-root.md`. It is not the connection’s “sudo -i after login” tick.

## Evidence

- **ℹ️** `Jobs.Batch.run` logs in, then calls `sudo()` only when `connection.sudo_after_login` is set. `src/Jobs/Batch.vala`.
- **ℹ️** `inject` sends `lxc-attach` only when `connection.kind` is `LXC`. A host skips that and feeds `script.body` at the shell `run()` left behind.
- **ℹ️** `Jobs.SudoLogin.sudo` is `sudo -i`, then the sudo password, then `WAIT_ROOT_PROMPT`. A host batch never reaches it unless that connection tick is on.
- **ℹ️** Interactive Open uses the same connection tick (`Jobs.OpenSession`). That path was not the test.

## Root cause

- **💩** Elevation for a batch follows the connection, and a script has no run-as flag. A host whose connection tick is off stays the login user. A container still looks like root because attach does that on its own.

## Proposed fix

- **🔷** After the script tick exists, a host batch whose script is ticked run-as-root calls the existing `sudo()` before `inject`. A host whose script is not ticked stays the login user.
- **🚫** Treating “sudo -i after login” on the connection as the batch decision.
- **🚫** A second sudo implementation beside `Jobs.SudoLogin.sudo`.
- **💩** How the same tick behaves on an LXC row (`lxc-attach` as root versus the login user) is open. This report is the host path.

## Attempts / changelog

- **ℹ️** 2026-11-18 — logged from a host batch that did not become root. No code change.

## Next

- **⏳** **🔷** Script tick and save-time authentication: `docs/bugs/2026-11-18-script-run-as-root.md`.
- **⏳** **💩** Confirm on the host that was tested whether “sudo -i after login” was ticked. The code path above does not need that to explain a host that stayed the login user.
