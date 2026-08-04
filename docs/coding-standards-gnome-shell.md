# GNOME Shell extension coding standards

Mandatory for AI agents editing `resources/extension/**`. Based on
[Javad Rahmatzadeh’s EGO / AI reference](https://blogs.gnome.org/jrahmatzadeh/2026/07/27/ego-ai-reference/)
(also on [GNOME Discourse](https://discourse.gnome.org/t/javad-rahmatzadeh-an-open-letter-to-ai-for-generating-gnome-shell-extensions/37265);
now part of [gjs.guide](https://gjs.guide/) best practices). Follow official
[EGO Review Guidelines](https://gjs.guide/extensions/review-guidelines/) when
touching reviewable patterns.

**RooTerm context:** the bundled extension is **maintained product code**,
installed by the app into the user extensions dir — not an EGO upload of
AI-generated personal experiments. Do **not** add the “Generated with AI for
personal use” banner to these files.

---

## Maintainership and completeness <!-- section: ego-maintainership -->

- Do not leave empty `enable()` / `disable()` stubs or placeholder modules.
- Generated scratch extensions (outside this tree) must include the AI notice
  and must **not** be published to extensions.gnome.org unless the author can
  read, debug, and maintain the JavaScript.
- Prefer complete, reviewable diffs over large unfinished scaffolds.

## Avoid unnecessary try-catch <!-- section: ego-try-catch -->

Do not wrap calls that do not throw in normal use: `destroy()`, `connect()`,
`disconnect()`, `abort()`, `GLib.Source.remove()` / `GLib.source_remove()`.

```javascript
// Bad
if (this._sourceId) {
    try {
        GLib.source_remove(this._sourceId);
    } catch (e) {
    }
    this._sourceId = null;
}

// Good
if (this._sourceId) {
    GLib.source_remove(this._sourceId);
    this._sourceId = 0;
}
```

`try` / `catch` is fine for I/O, D-Bus `call_finish`, JSON parse, and APIs
that genuinely throw across Shell versions (document why).

## Avoid unnecessary checks <!-- section: ego-unnecessary-checks -->

Do not use optional chaining (`?.()`) or `typeof x === 'function'` for
methods that always exist on the targeted API.

**Exception (RooTerm):** `metadata.json` lists multiple `shell-version`
values. Feature-detect **only** at genuine cross-version API boundaries
(e.g. `Meta.Window.hide_from_window_list`, `Main.wm.skipNextEffect`,
`Meta.WaylandClient` constructors). Prefer that over try/catch for missing
methods. Do not sprinkle typeof/optional checks on guaranteed members.

```javascript
// Bad — own method always exists
this.beep?.();
if (typeof this.beep === 'function') {
    this.beep();
}

// Good — cross-version Shell API
if (typeof win.hide_from_window_list === 'function') {
    win.hide_from_window_list();
}
```

Target clean code per version where possible; see the
[EGO Port Guide](https://gjs.guide/extensions/upgrading/) when multi-version
is required.

## Lifecycle and destruction <!-- section: ego-lifecycle -->

- Do **not** use `this._destroyed` / `this._enabled` flags to paper over
  lifecycle bugs. After `destroy()`, null the reference and never use it.
- Custom `destroy()` order: remove timeouts/sources → disconnect signals →
  release children/resources → `super.destroy()` last.
- Override `destroy()` on GObject widgets; do **not** connect a `destroy`
  signal solely for cleanup.

```javascript
// Bad
this._signal = this.connect('destroy', this._onDestroy.bind(this));

// Good
destroy() {
    // cleanup …
    super.destroy();
}
```

## Ownership and cleanup <!-- section: ego-cleanup-ownership -->

- Each class cleans up what it creates (signals, timeouts, Soup, cancellables,
  D-Bus watches/exports). No “create here, destroy elsewhere” spaghetti.
- Keep `enable()` and `disable()` adjacent on the entry-point class.
- Keep timeout **removal next to creation**. If a method may run again, remove
  any existing source before adding a new one; store the id on `this`.

```javascript
// Good
if (this.dockTimeoutId) {
    GLib.source_remove(this.dockTimeoutId);
    this.dockTimeoutId = 0;
}
this.dockTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
    this.dockTimeoutId = 0;
    // …
    return GLib.SOURCE_REMOVE;
});
```

Do not fire-and-forget repeating or re-entrant timeouts without an id field.

## Modules and entry point <!-- section: ego-modules -->

- Keep `extension.js` thin: wire `enable` / `disable` and own top-level
  watches only.
- One responsibility per file (PascalCase class modules under
  `resources/extension/`).
- Prefer helpers over copy-paste; shared non-UI utils must not import `St`,
  `Clutter`, `Gtk`, `Gdk`, or `Adw` if ever shared with prefs.
- Prefs UI lives in the **Vala app**, not a Shell `prefs.js`. If a Shell prefs
  process is ever added, put its modules under `prefs/`.

## UI and formatting <!-- section: ego-ui-format -->

- Icons: `St.Icon` / `icon_name` in Shell UI — never Unicode emoji as icons.
- Progress: real widgets (`ui.BarLevel`, `St.Bin`), not ASCII bars.
- Max line length **200** characters (EGO review UI).
- No comments that restate JavaScript or narrate trivial lines. Prefer clear
  names. Short “why” comments for non-obvious Shell/Mutter constraints are OK.

## D-Bus over subprocesses <!-- section: ego-dbus -->

- Prefer D-Bus to the RooTerm app (`Const.js` destinations) over spawning
  shell commands from the extension.
- Heavy work stays in the app; the Shell process stays thin.
- Last-resort spawn (e.g. Toggle when the bus call fails) must stay rare,
  logged, and justified in a short comment.

## Settings <!-- section: ego-settings -->

If the extension gains its own GSettings schema:

1. Set `"settings-schema"` in `metadata.json`.
2. Call `this.getSettings()` with **no** schema-id argument.
3. Do not stash the schema id as a file-level constant.

RooTerm currently reads toggle/layout from the app config JSON / app D-Bus —
keep that unless a plan introduces an extension schema.

## Version bumps <!-- section: ego-version -->

After behavioural changes under `resources/extension/`, bump
`metadata.json` `"version"` so `GnomeShell.ensure` upgrades the installed
copy. See `docs/build-rules.md`.
