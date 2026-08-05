# Manual auth still feeds password / newline into VTE

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed out 2026-08-05

**Started:** 2026-08-04

---

## Problem

- **🔷** Connection **Hebe Haven** (and any host) with Auth = **Manual** should leave the VTE alone for login and the interactive shell — user types everything.
- **🔷** **Actual:** something still injects into the session (line breaks / password-like noise) so the command line is disrupted.
- **ℹ️** Same host previously hit empty-password auto-feed as “Heebee Haven 24 Hour” / `hebe 24hr` when auth was password (`docs/bugs/done/2026-08-01-FIXED-tab-password-localhost-tree.md`).

### Reproduction

1. Edit connection → Auth **Manual** → Save.
2. Open the connection; type password (and any 2FA) yourself; reach a shell.
3. **Expected:** no `feed_child` of credentials or bare `\n` during login or at the shell.
4. **Actual:** job still auto-feeds on password prompt detection.

---

## Evidence

- **✔️** `Terminal.Ssh.spawn` skips libsecret when `auth == "manual"` (does not load `pass`).
- **✔️** `Dialog.Connection` save sets `auth = "manual"` and `pass = ""` (unless sudo keeps a secret for elevation).
- **✔️** `Jobs.OpenSession.login` always `expect(WAIT_SSH_PASSWORD)` then:
  - passphrase if set, else `feed_child((pass + "\n").data)`.
- **✔️** No `auth == "manual"` branch in `OpenSession.login` / `SshLogin.login`.
- **✔️** With manual, `pass` is usually empty → feed is **`"\n"` only**. Race: prompt classified → expect returns → feed runs after the user already submitted → newline lands on the **shell** (or mid-password).

---

## Root cause

- **✔️** Manual means “user owns auth,” but interactive login still uses the password auto-feed path. Empty (or leftover) `pass` → injected newline / password into the VTE.

---

## Fix applied

- **✔️** `OpenSession.login` / `SshLogin.login`: when `auth == "manual"`, wait for shell only (host-key / 2FA / password classification continue; never `feed_child` credentials).
- **🚫** Skip-feed-when-empty; sudo-after-login unchanged.

---

- **✅** 2026-08-05 — user: clean up fixed bugs → `done/`.

## Next

- **✅** 2026-08-05 — closed out; moved to `docs/bugs/done/`.
