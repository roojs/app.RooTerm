# Script tick for root, and authenticate on save

> Pointer: `docs/bug-fix-process.md` (emoji).
> Related: `docs/bugs/2026-11-18-batch-host-no-sudo.md`.
> Related: `docs/plans/done/0.23-DONE-script-sender.md`.

**Status:** ⏳ requirement logged. No code change.

**Started:** 2026-11-18

---

## Problem

- **🔷** A script has no choice of who it runs as. The body always goes out as whoever the batch shell already is.
- **🔷** Edit Command needs a tick box: run as root, or run as the logged-in user.
- **🔷** Save of a script that runs as root must authenticate the person at the keyboard before the row is written. Changing that script and saving again must authenticate again.
- **🔷** Run/Test saves through the same path (`Tab.Script.Edit.on_save_click`). It must not skip the authentication.
- **🔷** Authentication failing, or the user dismissing it, leaves the stored row unchanged.
- **🔷** A script ticked off (logged-in user) saves as it does now, with no extra authentication.
- **🔷** The host batch that stayed the login user is `docs/bugs/2026-11-18-batch-host-no-sudo.md`. This tick is what that batch should obey.

## Evidence

- **ℹ️** `script` columns in `src/SQT/Script.vala` are the Argus set plus `success_regex`. There is no run-as column. `task.run_as` exists on the Argus task table and is not set from Edit Command.
- **ℹ️** Edit Command is nickname, body, and success criteria. Save and Run/Test both call `on_save_click`. `src/Tab/Script/Edit.vala`.
- **ℹ️** `Jobs.Batch.run` becomes root only when the connection has `sudo_after_login`. The script is not consulted.

## Root cause

- **✔️** Run-as was left on the connection (`sudo_after_login`). The script row and the edit page have nowhere to store or ask for it, and nothing asks the user to prove they may save a root script.

## Proposed fix

- **🔷** Tick box on Edit Command, with the success criteria. Label: run as root. Off means the logged-in user.
- **💩** Existing rows load with the tick off. A new command starts off. That keeps today’s scripts as the login user until someone ticks them and authenticates.
- **🔷** Save and Run/Test, when the tick is on, authenticate before `store.save`. A dismissed or failed authentication does not write the row and does not open Hosts to execute.
- **🔷** The same gate applies when the tick was already on and the nickname, body, success criteria, or the tick itself changed.
- **💩** How to authenticate is open. It has to be a real check the user cannot click past (policy kit, or an equivalent prompt that fails closed). The check is in this bug. It is not a follow-up.
- **🚫** A connection-level tick as a substitute for the script tick.
- **🚫** Writing the row first and authenticating after.

### Where the tick sits

```
+------------------------------------------------------+
| [Back]                 Edit Command       [Run/Test] |
+------------------------------------------------------+
| nickname   [ apt upgrade                           ] |
|                                                      |
| Command to Run                                       |
| ...                                                  |
| Success criteria                                     |
| [ SUCCEEDED                                        ] |
| [ ] Run as root                                      |
+------------------------------------------------------+
| [Delete]                                      [Save] |
+------------------------------------------------------+
```

## Attempts / changelog

- **ℹ️** 2026-11-18 — logged with the host batch that did not become root. No code change. Authentication mechanism left open.

## Next

- **⏳** **💩** Pick the authentication mechanism, then propose the column and the `on_save_click` gate as Remove / Replace with fences.
- **⏳** **🔷** After the tick exists, the host batch in `docs/bugs/2026-11-18-batch-host-no-sudo.md` calls `sudo()` only when it is on.
