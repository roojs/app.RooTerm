# Preferences: re-capturing the current toggle key triggers show/hide

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user verified 2026-08-06

**Started:** 2026-08-06

**Related:**

- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-preferences-window-and-controls.md` — original capture + `block_toggle`
- **ℹ️** `docs/bugs/done/2026-08-01-FIXED-toggle-key-tooltip-and-binding.md` — media-keys `rooterm --toggle`
- **ℹ️** `src/Dialog/RowAccel.vala` → rename to `RowKeySelect.vala`
- **ℹ️** commit `586858f` — prefs → `RowAccel` / D-Bus rows dropped `block_toggle`

---

## Problem

- **🔷** Preferences → Toggle key → click capture → press the **already-bound** key (e.g. F1) → **show/hide** fires instead of accepting that key again.
- **🔷** Capturing a **different** key works.
- **🔷** Feels intermittent (depends on whether the pressed key is the live global binding).

---

## Evidence

- **✔️** Pre-row Preferences (`586858f^`):

  - Capture start set `window.block_toggle = true`
  - Escape / success / fill / close cleared it
  - Key controller was on the **Preferences window**

- **✔️** Current `RowAccel`:

  - Sets `capturing` only — **no** `block_toggle`
  - Controller is on the ActionRow only
  - Global toggle is still media-keys → `rooterm --toggle` (`GnomeShell.ensure_toggle_binding`)

- **✔️** `DBus.toggle` early-returns when `window.block_toggle` (still used by Shell restart dialog)

- **💩** Settings-daemon owns the live accelerator; that key often never reaches GTK capture. `block_toggle` alone stops hide/show but leaves “Press a key…” stuck unless the binding is released during capture.

---

## Root cause

- **✔️** Regression: prefs split to `RowAccel` omitted `block_toggle` while capturing.
- **✔️** Re-pressing the **current** toggle key hits the **global** media-keys shortcut (`rooterm --toggle`) instead of the capture controller. A different key is not bound → arrives at `EventControllerKey` → works.
- **✔️** If capture temporarily clears the media-keys slot, finishing with the **same** string must still call `ensure_toggle_binding` — GObject `notify["toggle-key"]` may not fire when the value is unchanged, so relying on `config_update` alone would leave the binding empty.

---

## Proposed fix

- **🔷** Rename ``RowAccel`` → ``RowKeySelect`` (file ``RowKeySelect.vala``; ``meson.build``).
- **🔷** ``RowKeySelect`` stays reusable for future **app-local** shortcut prefs.
- **🔷** Add property ``block_desktop`` (default ``false``): desktop-wide binding — capture must block toggle + release/restore media-keys + in-app ``win.toggle`` accels.
- **🔷** Only Preferences’ ``toggle-key`` row sets ``block_desktop = true`` and supplies ``window``.
- **🚫** Do not run the media-keys / ``block_toggle`` dance for ordinary app accelerators.

### Rename

- **Remove** `src/Dialog/RowAccel.vala`
- **Add** `src/Dialog/RowKeySelect.vala` (contents below)
- **meson.build:** `RowAccel.vala` → `RowKeySelect.vala`

### `src/Dialog/RowKeySelect.vala`

#### Add

```vala
public class RowKeySelect : Row
{
	public Gtk.Button button;

	/**
	 * Main window for desktop capture (``block_toggle`` / media-keys).
	 * Set with {@link block_desktop} for ``toggle-key``; unused for app-local accels.
	 */
	public MainWindow window;

	/**
	 * True when this accelerator is owned by the desktop (media-keys), not the app.
	 * Capture then blocks toggle and temporarily clears that binding.
	 */
	public bool block_desktop { get; set; default = false; }

	private bool capturing = false;

	/**
	 * @param config Chrome settings
	 * @param key Hyphenated string property (``toggle-key``)
	 */
	public RowKeySelect(Config config, string key)
	{
		base(config, key);
		this.button = new Gtk.Button.with_label("") {
			valign = Gtk.Align.CENTER
		};
		this.button.clicked.connect(() => {
			this.capturing = true;
			this.button.label = "Press a key…";
			if (!this.block_desktop) {
				return;
			}
			this.window.block_toggle = true;
			var app = this.window.application as Application;
			if (app != null) {
				app.set_accels_for_action("win.toggle", {});
			}
			try {
				this.window.shell.ensure_toggle_binding("");
			} catch (GLib.Error e) {
				GLib.warning("toggle binding: %s", e.message);
			}
		});
		((Adw.ActionRow) this.row).add_suffix(this.button);
		((Adw.ActionRow) this.row).set_activatable_widget(this.button);

		var keys = new Gtk.EventControllerKey() {
			propagation_phase = Gtk.PropagationPhase.CAPTURE
		};
		keys.key_pressed.connect((keyval, keycode, state) => {
			if (!this.capturing) {
				return false;
			}
			if (keyval == Gdk.Key.Escape) {
				this.capturing = false;
				var value = Value(typeof(string));
				this.read(ref value);
				this.button.label = value.get_string();
				if (this.block_desktop) {
					this.window.block_toggle = false;
					var app = this.window.application as Application;
					if (app != null) {
						app.set_accels_for_action("win.toggle", {
							value.get_string()
						});
					}
					try {
						this.window.shell.ensure_toggle_binding(value.get_string());
					} catch (GLib.Error e) {
						GLib.warning("toggle binding: %s", e.message);
					}
				}
				return true;
			}
			if (keyval == Gdk.Key.Shift_L || keyval == Gdk.Key.Shift_R
					|| keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R
					|| keyval == Gdk.Key.Alt_L || keyval == Gdk.Key.Alt_R
					|| keyval == Gdk.Key.Meta_L || keyval == Gdk.Key.Meta_R
					|| keyval == Gdk.Key.Super_L || keyval == Gdk.Key.Super_R) {
				return true;
			}
			var accel = Gtk.accelerator_name(
				keyval,
				state & Gtk.accelerator_get_default_mod_mask()
			);
			if (accel == null || accel.length == 0) {
				return true;
			}
			this.capturing = false;
			this.button.label = accel;
			this.send(accel);
			if (this.block_desktop) {
				this.window.block_toggle = false;
				var app = this.window.application as Application;
				if (app != null) {
					app.set_accels_for_action("win.toggle", { accel });
				}
				try {
					this.window.shell.ensure_toggle_binding(accel);
				} catch (GLib.Error e) {
					GLib.warning("toggle binding: %s", e.message);
				}
			}
			return true;
		});
		((Gtk.Widget) this.row).add_controller(keys);
	}

	public override void fill()
	{
		this.loading = true;
		if (this.capturing && this.block_desktop) {
			this.window.block_toggle = false;
			var cur = Value(typeof(string));
			this.read(ref cur);
			var app = this.window.application as Application;
			if (app != null) {
				app.set_accels_for_action("win.toggle", { cur.get_string() });
			}
			try {
				this.window.shell.ensure_toggle_binding(cur.get_string());
			} catch (GLib.Error e) {
				GLib.warning("toggle binding: %s", e.message);
			}
		}
		this.capturing = false;
		var value = Value(typeof(string));
		this.read(ref value);
		this.button.label = value.get_string();
		this.loading = false;
	}
}
```

(Keep the existing file header / namespace / class docblock style from `RowAccel.vala`, updated for the new name.)

### `src/Dialog/Preferences.vala`

#### Remove

```vala
this.add("toggle-key", new RowAccel(this.config, "toggle-key"), keyboard);
```

#### Replace with

```vala
var toggle = new RowKeySelect(this.config, "toggle-key") {
	block_desktop = true,
	window = this.window
};
this.add("toggle-key", toggle, keyboard);
```

#### Add (in `close_request`, before hide)

```vala
var toggle = this.rows.get("toggle-key") as RowKeySelect;
if (toggle != null) {
	toggle.fill();
}
```

(`fill` restores binding if capture was still active.)

### `meson.build`

#### Remove

```meson
'src/Dialog/RowAccel.vala',
```

#### Replace with

```meson
'src/Dialog/RowKeySelect.vala',
```

---

## Attempts / changelog

- **✔️** 2026-08-06 — traced regression to `586858f` dropping `block_toggle`; media-keys steals current key.
- **🔷** 2026-08-06 — user: ``block_desktop`` (not ``global``); rename ``RowAccel`` → ``RowKeySelect``.
- **✔️** 2026-08-06 — applied: ``RowKeySelect`` + ``block_desktop``; Preferences toggle-key wired; meson updated.
- **✅** 2026-08-06 — user: works fine; close.

## Next

- (none — closed)

