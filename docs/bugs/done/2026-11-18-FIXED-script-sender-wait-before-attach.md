# Script sender waits before attach and never runs the command

> Pointer: `docs/bug-fix-process.md` (emoji).
> Related: `docs/plans/done/0.23-DONE-script-sender.md`.

**Status:** ✅ FIXED — user closed out 2026-11-18

**Started:** 2026-11-18

---

## Problem

- **🔷** Script sender against an LXC container opens the terminal, then sits there before `lxc-attach`.
- **🔷** `lxc-attach` should run as soon as the host shell is up (after `sudo -i` when that host has it).
- **🔷** The pause belongs after attach, inside the container. On a plain host it belongs after that shell, before the script body.
- **🔷** Show the pause as `about to run` and five dots in the window title. Remove one dot each second. As soon as one dot is showing, send the script body.
- **🔷** On this run the command in the script never ran.

## Evidence

- **ℹ️** Reproduce: Script sender → tick a container → Run. Terminal comes up, then a stall, then attach (late). The script line is not sent.
- **ℹ️** `Dialog.Plan` starts one `GLib.Timeout.add(10000)` at Run. That callback sets `sending` and calls `feed` on every job.
- **ℹ️** `append_job` does not call `feed` until `sending` is true. A shell that is already up still waits out that timer.
- **ℹ️** `Jobs.Batch.inject` is what `feed` starts. The first thing it does for an LXC row is `lxc-attach`. The script lines are the loop after that prompt comes back.
- **ℹ️** So the stall is the ten-second timer, and it sits in front of attach. The body cannot start until that timer fires and attach's prompt wait returns.
- **ℹ️** Title today is `executing .... n/N` during login, then `starting...` at the same moment attach is sent. Dots do not count down.
- **💩** The body was skipped because the run was still in that pre-attach wait. The `--debug` log below rules that out.
- **✔️** 2026-11-18 11:23 — container `website`. `shell up` and `attach send` are the same instant. 265ms later `attach timeout` with state `WAIT_ROOT_PROMPT`. No `dots start`, no `body line`.
- **✔️** Login had already reached a root prompt (`sudo -i`). The cursor line still ended in `#`, so `SudoLogin` classified `WAIT_ROOT_PROMPT`. `expect` wanted `WAIT_SHELL_PROMPT` and treated that other state as failure.
- **ℹ️** About 800ms later the real container prompt is `root@website:~#`. A `#` prompt is a root prompt, so a shell-only wait would still fail after the cursor moved.

## Root cause

- **✔️** The ten-second gate is gone. Attach runs when the shell is up.
- **✔️** The body was not sent because the attach wait rejected the root prompt. That prompt is what a `sudo -i` host and `root@container:~#` both look like.
- **✔️** The first classification can also be the prompt still on the row the command was typed on. That row is not the next prompt.

## Proposed fix

- **🔷** A command wait ignores the cursor row the command was typed on. The next prompt is a later row.
- **🔷** That next prompt may be a shell prompt or a root prompt. Either one continues. Dots, then the body.
- **🔷** Empty success criteria: the title is `completed n/N`. The word success is only there when criteria is set.
- **🔷** Run is on the left. Close is on the right. Cancel stays the left button once the run has started.
- **🔷** The batch window is about forty percent wider and taller (1008×728, from 720×520).
- **💩** Batch terminal copies font and font scale from the visible main terminal, and uses the same `vte-host` / `vte-path` classes.

The hunks below are the first fix. They are already applied.

- **✔️** Drop the ten-second timer that delays `feed`. When the shell reaches `DONE`, call `feed` immediately.
- **🔷** `lxc-attach` stays the first step of `inject` for an LXC row, so it runs as soon as login (and sudo) finishes.
- **🔷** After that prompt (or straight away when the row is not a container), the window title is `about to run` and five `.` characters. Once a second, one `.` is removed. At a single `.`, `inject` sends the script lines.
- **🔷** Cancel during the dots still sets `halt` and does not send the body. The two-second delay before the Run button becomes Cancel stays (double-click guard).
- **💩** One target: the batch window title is the dots. Several targets in the wait at once would each write that title; last write wins. Revisit if a multi-target run needs dots on each chip.
- **💩** `Batch` needs the plan window to set the title. Field below, not a new method.
- **ℹ️** Landed in `docs/plans/done/0.23-DONE-script-sender.md`: the wait is after attach, shown as a shrinking dot row.

### `src/Jobs/Batch.vala`

#### Add — `plan` next to `script`

```vala
		public RooTerm.Dialog.Plan plan;
```

#### Replace with — after the `lxc-attach` block, before `var parts = this.script.body.split`

Count down, then fall through into the existing line loop. `halt` uses the same save already in `inject`.

```vala
			for (var dots = 10; dots > 0; dots--) {
				this.plan.title = string.nfill(dots, '.');
				if (dots == 1) {
					break;
				}
				GLib.Timeout.add(1000, () => {
					this.inject.callback();
					return false;
				});
				yield;
				if (this.halt) {
					this.target.is_cancelled = true;
					this.target.success = 1;
					this.target.ended = (int64) new GLib.DateTime.now_local().to_unix();
					this.targets.save(this.target);
					return;
				}
			}
```

### `src/Dialog/Plan.vala`

#### Remove — the `GLib.Timeout.add(10000, ...)` that sets `sending` and calls `feed`

Leave the two-second timeout that turns Run into Cancel.

#### Replace with — login success calls `feed` immediately

```vala
				this.opened++;
				if (this.finished == 0 && !this.sending) {
					this.title = "executing .... %d/%d".printf(this.opened, this.goal);
				}
				this.feed(job);
```

#### Add — `plan = this` on the `Jobs.Batch` constructor in `append_job`

```vala
				plan = this
```

---

## Attempts / changelog

- **ℹ️** 2026-11-18 — logged from a container run.
- **✔️** 2026-11-18 — ten-second gate removed. `feed` runs when the shell is `DONE`. `lxc-attach` is still the first step of `inject`. Dots then count 10 → 1 on the plan title. Body starts at one dot.
- **✔️** 2026-11-18 — `GLib.debug` at shell up, feed skip, attach send / prompt / timeout, dots start / one / halt, body start, blank skip, each body line, line prompt / timeout, body loop done. No timestamps. Run with `--debug`. Log: `~/.cache/rooterm/rooterm.debug.log`.
- **✔️** 2026-11-18 — log: attach died on `WAIT_ROOT_PROMPT` before dots. Wait now skips the typed row and accepts a shell or root prompt. Empty criteria titles are `completed n/N`. Run left, Close right. Window 1008×728. Batch font copied from the visible main terminal.
- **✔️** 2026-11-18 — countdown title is `about to run` plus five dots, not ten. Body still starts at one dot.
- **✔️** 2026-11-18 — one countdown for the batch, after every target has attached or failed login. Title order is `starting n/N` (no dots), then `about to run` for three seconds, then `running`, then `completed` only when every target has finished. Cancel is shown as soon as Run is pressed. Run and Cancel are different buttons, so there is no two-second delay.

## Next

- **⏳** **🔷** User verify on a container (`--debug`).
  - `prompt hold` on the old `#` row, then `prompt release`, then `attach prompt` with `WAIT_ROOT_PROMPT`.
  - Dots count down. `body line` follows `dots one`.
  - Title is `completed n/N` when success criteria is empty.
  - Run on the left. Cancel on the right while the run is going. Close replaces Cancel after Cancel or when the run finishes.
