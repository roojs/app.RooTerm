# Bug Fix Process

## Never hide bugs

**NEVER add protective or defensive checks** (null checks, fallbacks, "just in case" guards, swallowing errors, default values that mask bad state) **to mask failures or symptoms.** That only hides the problem: the underlying defect stays, and you fix the wrong layer.

**Aim for the root cause** — why the bad value, wrong path, or invalid state appears — **not** only what it triggers downstream (a crash, a warning, a bad UI). Fixing or silencing the trigger without fixing the source repeats the failure in another form.

## Required process

When fixing a bug, follow this order. Do not skip steps or apply code changes before approval.

### a) DEBUG first

- Reproduce the failure.
- **Issue log (`docs/bugs/`):** **Always** create or update a file under **`docs/bugs/`** **unless** the change is **trivial**: a **single line** and you already know it is the correct fix. Otherwise keep a **paper trail**:
  - **Resolved logs:** When a bug is **fully** fixed and verified, rename with **`FIXED`** in the filename and move to **`docs/bugs/done/`** (keep the same basename pattern). Active **`docs/bugs/`** holds OPEN investigations and non‑trivial in‑progress logs.
  - **Name:** **`YYYY-MM-DD-{short-slug}.md`** — use **today’s date** (calendar day you start or update the log) as the prefix, plus a **kebab-case** slug. Add **`FIXED`** in the name only when the bug is **fully** resolved and verified (e.g. `2026-07-30-FIXED-reconnect-skips-open-session-login.md`).
  - **Problem** — what's wrong, how to reproduce, expected vs actual.
  - **Attempts / changelog** — code or config changes (file + purpose); **debug code added** (file, what it logs, how to run).
  - **Conclusions** — what's ruled in/out, root cause if known, open questions.
  - **Record of what was tried** — enough that others don't repeat dead ends.
  - **After the fix** — final conclusion (link plan/commit if useful); remove temporary **`GLib.debug()`** when merged (note in the log if helpful).
- Add **minimal, targeted** logging—only what's needed to see the real values and control flow.
- Use **`GLib.debug()`** for debug output. Do not add method/class name in the message—file and line are already in the output.
- Pass **`--debug`** so debug lines go to stderr and **`~/.cache/rooterm/rooterm.debug.log`**.
- Prefer **readable output**: paths, IDs with context, "found"/"not found"; length alone is rarely enough.
- Run and capture evidence. Do not guess.

### b) Understand the real issue

- From the evidence, identify the **root cause** (wrong data, wrong place, wrong assumption, missing step) — not merely where it exploded or what symptom appeared first.
- Document it in the bug log: what's wrong, **why** it happens, and what would be wrong to "fix" if you only patched the trigger.

### c) Propose fix

- Propose a concrete fix that addresses the root cause, not the symptom.
- Describe the change and where it goes. No defensive workarounds.
- When the fix needs code edits, put **verbatim** **`#### Remove`** / **`#### Replace with`** / **`#### Add`** fences in the bug log under the topic that owns the change — same contract as **`docs/guide-to-writing-plans.md`** (**Edit syntax contract**, **Code proposals — one place, not two**). Do not leave “change X to Y” as prose only.

### d) Get approval

- Present the diagnosis and proposed fix to the user (or reviewer).
- Wait for explicit approval before editing code.

### e) Only apply after approval

- Implement the approved fix only.
- Do not add extra "safety" checks or fallbacks unless they were part of the approved fix.

## Plans vs bugs

- **Plans** (`docs/plans/`) — feature work, design, ordered delivery.
- **Bugs** (`docs/bugs/`) — something that already should work and does not. Do **not** fold accidental regressions into a feature plan as “extra scope.”

## Bug log markup (emoji + shape)

Bug logs in **`docs/bugs/`** use the **same emoji legend** as plans —
**`docs/guide-to-writing-plans.md`** (**Discussion style (emoji prefixes)**). Do
**not** write unmarked mandate bullets.

| Marker | Use in bug logs |
| ------ | ---------------- |
| 🔷 | User-stated symptom, requirement, or approved fix direction |
| 💩 | Agent-inferred hypothesis, optional debug, or proposed change not yet confirmed by the user |
| ℹ️ | Pointers (log path, related plan, file, prior bug) |
| 🚫 | Ruled out / do not implement |
| ⏳ | Open work (always pair with 🔷 or 💩) |
| ✔️ | Agent claims implemented / evidence captured — not user-verified |
| ✅ | User verified fixed on device |

**Minimum shape for a non-trivial bug log:**

1. **Title** + **Status:** line (may use ⏳ alone for overall state).
2. **Problem** — 🔷 expected vs actual; reproduction bullets.
3. **Evidence** — nested bullets (prefer over tables); prefix with ℹ️ / ✔️ as appropriate.
4. **Root cause** — only after evidence; mark ✔️ when confirmed from code/logs, not guesses.
5. **Proposed fix** — 🔷 / 💩 clearly separated; **inline code fences** (Remove / Replace with / Add) when applying will touch Vala.
6. **Attempts / changelog** + **Next** — ⏳ items paired with provenance.

**🚫** Unmarked paragraphs that read like requirements. **🚫** Promoting ✔️ → ✅ without the user.

Example status line:

`**Status:** ⏳ root cause confirmed; fix proposed — await apply approval`

## Summary

1. **DEBUG first** (including **`docs/bugs/YYYY-MM-DD-*.md`** unless a **one-line** fix is already certain) → 2. **Understand real issue** → 3. **Propose fix** (emoji + fences) → 4. **Get approval** → 5. **Apply only after approval**

No guards or symptom-only patches that hide the real bug.
