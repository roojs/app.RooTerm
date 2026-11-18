# Script sender stays in one window

> Pointer: `docs/bug-fix-process.md` (emoji).
> Related: `docs/plans/done/0.23-DONE-script-sender.md`.

**Status:** ✅ FIXED — user closed out 2026-11-18

**Started:** 2026-11-18

---

## Problem

- **🔷** Double-click a command and the play button both open the edit script page.
- **🔷** From edit, Back returns to the list. Run goes on to pick hosts and run again.
- **🔷** List, edit, host picker, and the run all live in the one Script sender window.
- **🔷** Cancel and Back change the page. They do not open or close another window.
- **🔷** The window is the controller. It builds every page up front. The header buttons flip the visible page.

## Evidence

- **ℹ️** `Tab.Script` is the list window (shell role `script`). Row activate calls `Dialog.Script.open`. Play builds a new `Dialog.Plan`.
- **ℹ️** `Dialog.Script` is its own modal window (shell role `script-form`). Cancel hides that window. Test builds another `Dialog.Plan`.
- **ℹ️** `Dialog.Plan` is a third window (shell role `plan`). It already swaps its own body between the host tree and the terminals.
- **ℹ️** A run therefore leaves the list up, the edit form up, and a plan window up.

## Root cause

- **✔️** Each step is an `Adw.Window` with its own header. Moving to the next step calls `present` on a new window.

## Proposed fix

- **🔷** One window: `RooTerm.Dialog.Script`. Shell role stays `script`.
- **🔷** A `Gtk.Stack` in that window is the directory of pages. One page is visible. There is no tab strip to click.
- **🔷** Pages, in order: the command list, Edit Command, Hosts to execute, the terminals.
- **ℹ️** `list`, `edit`, `plan`, and `run` are names in the code only. They are not button labels. The screens are Script sender, Edit Command, Hosts to execute, and the terminals.
- **🔷** Each page is built with the sender window and asks that window to change page. The pages are not windows.
- **🔷** The header bar stays on the window. Showing a page repacks the buttons for that page.
- **🔷** Back is always the left button. On the terminals it appears only after Cancel has gone. Where it goes is in the table under Where Back goes.
- **💩** The window size is the run size, 1008×728, so the terminals fit on every page.
- **🚫** A visible notebook the user clicks between.
- **🚫** New shell roles for the form or the plan. Those windows go away.

### Where Back goes

| Screen | Back goes to |
| --- | --- |
| Script sender (the command list) | No Back. Close hides the window. |
| Edit Command | Script sender, the command list. |
| Hosts to execute (the screen with Run) | Edit Command. |
| Terminals, after Cancel or when every machine has finished | Edit Command. |

### Classes

| Class |
| --- |
| `RooTerm.Dialog.Script` |
| `RooTerm.Tab.Script.List` |
| `RooTerm.Tab.Script.Edit` |
| `RooTerm.Tab.Script.Hosts` |
| `RooTerm.Tab.Script.Run` |

### What stays while you test

The usual loop is one host. Run/Test, see if the command works, Back to Edit Command, change the text, Run/Test again. Hosts to execute should already be ticked, so that second screen is a flip-through, not a fresh pick.

- **🔷** While Edit Command, Hosts to execute, and the terminals are the screens in use, the command text stays as it was left, and the host ticks stay as they were left.
- **🔷** A machine is unticked when its output matches the success criteria. That one is not pre-selected for the next run.
- **🔷** Run/Test in that loop does not clear the ticks and does not reload the form from the saved row.
- **🔷** Back from Edit Command to the command list ends the loop. The next open of Edit Command from the list loads the saved command and starts with no host ticks.
- **🔷** Opening a different command, or Add command, is a new visit. It starts with that row’s saved text and no host ticks.
- **ℹ️** `Dialog.Plan.open` used to build a new draft task and call `picks.clear()` on every Test. That window is gone. Ticks now stay until Edit is opened again from the list.
- **🚫** Remembering the ticks in the database and restoring them on the next visit from the list.

### Buttons

- **🔷** Script sender — Close on the left (hides the window). Add command on the right (empty Edit Command page).
- **🔷** Edit Command — four buttons. Header: Back on the left (the command list), Run/Test on the right (saves, then Hosts to execute). Bottom: Delete on the left, Save on the right (writes the row, stays on the page). Save is not the accent button.
- **🔷** Delete is only there when the row already exists.
- **🔷** Hosts to execute — Back on the left (Edit Command). Run on the right (the terminals).
- **🔷** Terminals — Cancel stays on the right while the jobs are going, then disappears. Back and Cancel are not on screen together. Once Cancel is gone, Back on the left returns to Edit Command.

### Pages

One window. The header is the only way between pages.

#### List

Double-click a row, or the play button, opens Edit.

```
+------------------------------------------------------+
| [Close]            Script sender      [Add command]  |
+------------------------------------------------------+
| [ Search commands                                  ] |
|                                                      |
| Nickname            Command                       >  |
| apt upgrade         apt upgrade -y && echo "OK"  [>] |
| disk check          df -h                         [>] |
+------------------------------------------------------+
```

#### Edit

Back goes to the command list. Run/Test saves, then opens Hosts to execute. Save writes the row and stays here. Delete is only there when the command already exists.

```
+------------------------------------------------------+
| [Back]                 Edit Command       [Run/Test] |
+------------------------------------------------------+
| nickname   [ apt upgrade                           ] |
|                                                      |
| Command to Run                                       |
| These are the commands to be sent...                 |
| +--------------------------------------------------+ |
| | apt upgrade -y && echo "SUCCEEDED"               | |
| +--------------------------------------------------+ |
|                                                      |
| Success criteria                                     |
| To check a command worked, add && echo "SUCCEEDED"  |
| [ SUCCEEDED                                        ] |
+------------------------------------------------------+
| [Delete]                                      [Save] |
+------------------------------------------------------+
```

#### Hosts to execute

Code name `plan`. Back goes to Edit Command. Run opens the terminals.

```
+------------------------------------------------------+
| [Back]        Hosts to execute 'apt upgrade'   [Run] |
+------------------------------------------------------+
| [ Search hosts          ] [Hosts v] [Select all]     |
|                                                      |
|  [ ] sgfs1                                           |
|      [x] web-release64                               |
|  [ ] sgap1                                           |
|      [ ] web-release64                               |
+------------------------------------------------------+
```

#### Terminals, while the machines are coming up

Code name `run`. Title is `starting n/N`. No dots. Cancel is on the right. Back stays off this page until Cancel disappears.

```
+------------------------------------------------------+
|                         starting 1/3        [Cancel] |
+------------------------------------------------------+
|                                                      |
|  root@web-release64:~#                               |
|                                                      |
|                                                      |
+------------------------------------------------------+
| [web-release64] [web-release-readonly] [bee]         |
+------------------------------------------------------+
```

#### Terminals, every terminal armed

`about to run ...` then `..` then `.` over three seconds. Then the commands go out and the title becomes `running`.

```
+------------------------------------------------------+
|                    about to run ...         [Cancel] |
+------------------------------------------------------+
|  ...terminals...                                     |
+------------------------------------------------------+
| [web-release64] [web-release-readonly] [bee]         |
+------------------------------------------------------+
```

#### Terminals, after Cancel or when every machine has finished

Cancel has disappeared. Back is on the left and goes to Edit Command.

```
+------------------------------------------------------+
| [Back]                    completed 3/3              |
+------------------------------------------------------+
|  ...terminals stay on screen...                      |
+------------------------------------------------------+
| [web-release64] [web-release-readonly] [bee]         |
+------------------------------------------------------+
```

### `src/Dialog/Script.vala`

`RooTerm.Dialog.Script`. The window. Its stack holds `List`, `Edit`, `Hosts`, and `Run`. `show_page` is the only way to change tab.

#### Add

```vala
		private enum Page {
			LIST,
			EDIT,
			PLAN,
			RUN
		}

		/**
		 * Show one sender page and repack the header for it.
		 *
		 * @param page list, edit, plan, or run
		 */
		public void show_page(Page page)
		{
			this.stack.visible_child_name = page.to_string();
		}
```

#### Replace with — play and row activate

Both open the edit page for that row. Play does not build a plan window.

```vala
			button.clicked.connect(() => {
				var row = button.get_data<RooTerm.SQT.Script>("script-row");
				if (row == null) {
					return;
				}
				this.edit.load(row);
				this.show_page(Page.EDIT);
			});
```

```vala
			grid.activate.connect((position) => {
				var row = selection.get_item(position) as RooTerm.SQT.Script;
				if (row == null) {
					return;
				}
				this.edit.load(row);
				this.show_page(Page.EDIT);
			});
```

### `src/Tab/Script.vala`

#### Replace with — `RooTerm.Tab.Script.List`

The edit form now in `src/Dialog/Script.vala` moves to `RooTerm.Tab.Script.Edit`.

### `src/Dialog/Plan.vala`

#### Replace with — `RooTerm.Tab.Script.Hosts` and `RooTerm.Tab.Script.Run`

---

## Attempts / changelog

- **ℹ️** 2026-11-18 — logged from the three-window flow. No code change yet.
- **ℹ️** 2026-11-18 — page layouts (header buttons and body) drawn under Pages.
- **ℹ️** 2026-11-18 — edit is Back and Save on the header, Delete and Run/Test on the bottom. Back stays on the left. Cancel stays on the right and hides.
- **ℹ️** 2026-11-18 — Back destinations spelled out by screen. `list` / `edit` / `plan` / `run` noted as code names. Class replacement table added.
- **ℹ️** 2026-11-18 — command text and host ticks stay while testing one command. Both reset when Edit Command is opened again from the list.
- **ℹ️** 2026-11-18 — the window is `RooTerm.Dialog.Script`. Tabs are `RooTerm.Tab.Script.List`, `Edit`, `Hosts`, `Run`.
- **ℹ️** 2026-11-18 — implemented. `ninja -C build` succeeded.
- **ℹ️** 2026-11-18 — Run/Test is the header button. Save is on the bottom and is not the accent.
- **ℹ️** 2026-11-18 — Back from the terminals goes to Edit Command. Host search expands rows so matching children show.
- **ℹ️** 2026-11-18 — Run closes the previous terminal pages before opening the new ones, and selects the first new page.
- **ℹ️** 2026-11-18 — a host tick is cleared when that machine matches the success criteria.

## Next

- **⏳** **🔷** Open Script sender and walk list → edit → hosts → terminals → back. Ticks and the command text should survive that loop, and clear when the command is opened again from the list.
