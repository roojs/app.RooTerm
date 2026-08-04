# Preferences Cancel takes forever to close

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✔️ applied — awaiting device verify → promote to ✅ / `done/` when confirmed

**Started:** 2026-08-04

**Related:**

- **ℹ️** `docs/plans/0.15.1-DONE-prefs-process-dbus-cleanup.md` — Cancel snap restore via `Row.send` / `ConfigUpdate` (superseded UX)
- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-preferences-window-and-controls.md` — live apply prefs UX

---

## Problem

- **🔷** Preferences → Cancel → dialog takes a long time to disappear.
- **🔷** Prefs already update **live** via `ConfigUpdate`; Save/Cancel + snap undo do not match that model.
- **🔷** Want a single **Close** button; no Save; no undo on dismiss.

### Reproduction

1. Open Preferences (`Ctrl+,` or panel menu).
2. Press **Cancel** (even with no edits).
3. **Actual:** long pause before the window goes away (full snap restore via sync D-Bus).

---

## Evidence

- **✔️** Rows already `send` → `ConfigUpdate` on each control change (live).
- **✔️** Cancel `close_request` re-`send`s **every** snap key before Hide — blocks dismiss.
- **✔️** Save only Hides (keeps live values) — the useful half of the current chrome.

---

## Root cause

- **✔️** Dialog still implements apply-on-close / Cancel-revert on top of live apply. Cancel’s full snap restore is both the lag and the wrong UX.

---

## Proposed fix

- **🔷** One **Close** button (header end); remove **Save** and **Cancel**.
- **🔷** Live apply stays as-is (`Row.send` on change). Close only Shell-Hides — **no** snap, **no** undo, **no** `accepting`.
- **🚫** Partial snap restore. **🚫** Keep Save as suggested-action twin of Close.

### `src/Dialog/Preferences.vala`

#### Remove (fields)

```vala
		private bool accepting = false;
		private Gee.HashMap<string, string> snap {
			get;
			set;
			default = new Gee.HashMap<string, string>();
		}
```

#### Remove (header buttons + close_request + fill snap)

```vala
			var cancel = new Gtk.Button.with_label("Cancel");
			cancel.clicked.connect(() => {
				this.close();
			});
			var save = new Gtk.Button.with_label("Save") {
				css_classes = { "suggested-action" }
			};
			save.clicked.connect(() => {
				this.accepting = true;
				this.close();
			});
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			var no_max = new Gtk.GestureClick() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
				button = Gdk.BUTTON_PRIMARY
			};
			no_max.pressed.connect((n_press, x, y) => {
				if (n_press >= 2) {
					no_max.set_state(Gtk.EventSequenceState.CLAIMED);
				}
			});
			header.add_controller(no_max);
			header.pack_start(cancel);
			header.pack_end(save);
```

```vala
			this.close_request.connect(() => {
				if (!this.accepting) {
					foreach (var key in this.snap.keys) {
						this.rows.get(key).send(this.snap.get(key));
					}
				}
				this.accepting = false;
				this.window.dbus.call("Hide", new GLib.Variant("(s)", "preferences"));
				return true;
			});
```

```vala
		/**
		 * Reload rows from disk and refresh Cancel snapshots.
		 */
		public void fill()
		{
			this.accepting = false;
			this.config = Config.load();
			foreach (var row in this.rows.values) {
				row.config = this.config;
				row.fill();
			}
			this.snap.clear();
			foreach (var key in this.rows.keys) {
				var value = Value(this.rows.get(key).pspec.value_type);
				((GLib.Object) this.config).get_property(key, ref value);
				if (value.holds(typeof(int))) {
					this.snap.set(key, value.get_int().to_string());
					continue;
				}
				this.snap.set(key, value.get_string());
			}
		}
```

#### Replace with

```vala
			var close_btn = new Gtk.Button.with_label("Close");
			close_btn.clicked.connect(() => {
				this.close();
			});
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			var no_max = new Gtk.GestureClick() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
				button = Gdk.BUTTON_PRIMARY
			};
			no_max.pressed.connect((n_press, x, y) => {
				if (n_press >= 2) {
					no_max.set_state(Gtk.EventSequenceState.CLAIMED);
				}
			});
			header.add_controller(no_max);
			header.pack_end(close_btn);
```

```vala
			this.close_request.connect(() => {
				this.window.dbus.call("Hide", new GLib.Variant("(s)", "preferences"));
				return true;
			});
```

```vala
		/**
		 * Reload rows from disk.
		 */
		public void fill()
		{
			this.config = Config.load();
			foreach (var row in this.rows.values) {
				row.config = this.config;
				row.fill();
			}
		}
```

#### Keep (class doc — tweak live-only wording)

```vala
	 * hosting an {@link Adw.PreferencesPage}. Rows call ``ConfigUpdate`` via
	 * {@link Row.send}; this window does not write ``config.json``.
```

#### Replace with (class doc)

```vala
	 * hosting an {@link Adw.PreferencesPage}. Rows apply live via
	 * {@link Row.send} / ``ConfigUpdate``; Close only Hides (no undo).
	 * This window does not write ``config.json``.
```

---

## Attempts / changelog

- **ℹ️** 2026-08-04 — lag from Cancel snap restore before Hide.
- **ℹ️** 2026-08-04 — dropped partial-restore proposal; **🔷** Close-only / live / no undo.
- **✔️** 2026-08-04 — applied: Close only; removed Save/Cancel/`snap`/`accepting`; `close_request` only Hides.

## Next

- **⏳** **🔷** Device: Close dismisses immediately; slider changes stay after Close.
