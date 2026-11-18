# Script tick for root, and authenticate on save

> Pointer: `docs/bug-fix-process.md` (emoji).
> Related: `docs/bugs/done/2026-11-18-FIXED-batch-host-no-sudo.md`.
> Related: `docs/plans/done/0.23-DONE-script-sender.md`.

**Status:** closed for 0.1.5. Not verified on a machine.

**Started:** 2026-11-18

---

## Problem

- **🔷** A script has no choice of who it runs as. The body always goes out as whoever the batch shell already is.
- **🔷** Edit Command needs a tick box: run as root, or run as the logged-in user.
- **🔷** Save of a script that runs as root must authenticate the person at the keyboard before the row is written. Changing that script and saving again must authenticate again.
- **🔷** Run/Test saves through the same path (`Tab.Script.Edit.on_save_click`). It must not skip the authentication.
- **🔷** Authentication failing, or the user dismissing it, leaves the stored row unchanged.
- **🔷** A script ticked off (logged-in user) saves as it does now, with no extra authentication.
- **🔷** The host batch that stayed the login user is `docs/bugs/done/2026-11-18-FIXED-batch-host-no-sudo.md`. This tick is what that batch should obey.

## Evidence

- **✔️** `script.run_as_root` is a bool, default false. Edit Command has **Run as root** on the nickname row. Save and Run/Test write it in `on_save_click`. `src/SQT/Script.vala`, `src/Tab/Script/Edit.vala`.
- **✔️** A host batch calls `sudo()` when that flag is on. `docs/bugs/done/2026-11-18-FIXED-batch-host-no-sudo.md`.
- **✔️** A ticked save runs `pkexec /usr/bin/true` before `store.save`. Dismiss or failure leaves the stored row unchanged. PolicyKit may cache the grant. `task.run_as` is still unused.

## Root cause

- **✔️** Run-as was left on the connection (`sudo_after_login`). The script row and the edit page have nowhere to store or ask for it, and nothing asks the user to prove they may save a root script.

## Proposed fix

- **🔷** Tick box on Edit Command, on the nickname row. Label: run as root. Off means the logged-in user. A new command starts off.
- **💩** Existing rows load with the tick off. A new command starts off. That keeps today’s scripts as the login user until someone ticks them and authenticates.
- **🔷** Save and Run/Test, when the tick is on, authenticate before `store.save`. A dismissed or failed authentication does not write the row and does not open Hosts to execute.
- **🔷** The same gate applies when the tick was already on and the nickname, body, success criteria, or the tick itself changed.
- **✔️** The check is `pkexec /usr/bin/true` on this machine. Each ticked save tries it. A cached PolicyKit grant can succeed with no new dialog.
- **🚫** A connection-level tick as a substitute for the script tick.
- **🚫** Writing the row first and authenticating after.

### Where the tick sits

```
+------------------------------------------------------+
| [Back]                 Edit Command       [Run/Test] |
+------------------------------------------------------+
| nickname   [ apt upgrade           ]  [ ] Run as root |
|                                                      |
| Command to Run                                       |
| ...                                                  |
| Success criteria                                     |
| [ SUCCEEDED                                        ] |
+------------------------------------------------------+
| [Delete]                                      [Save] |
+------------------------------------------------------+
```

## Attempts / changelog

- **ℹ️** 2026-11-18 — logged with the host batch that did not become root. Authentication mechanism left open.
- **✔️** 2026-11-18 — column and Edit Command tick added so the host batch can obey them.
- **✔️** 2026-11-18 — ticked Save and Run/Test call `pkexec /usr/bin/true` before `store.save`. Failure shows “Run as root was not authorized” and does not write the row.

## Next

- **✔️** Closed for 0.1.5 without a desktop run. Confirm later: tick **Run as root**, Save, and see the PolicyKit prompt. Dismiss it and the stored command stays as it was.
