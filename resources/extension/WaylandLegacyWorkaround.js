import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';

import {DBUS_DEST, DBUS_PATH, DBUS_IFACE} from './Const.js';

/**
 * GNOME 48 Wayland duct-tape only — monkey-patches ShellService / Dock.
 *
 * Mutter only allows hide_from_window_list for processes spawned via
 * Meta.WaylandClient. On first unowned storeRole, Quit(true) and respawn through
 * WaylandClient (no confirm dialog). Also applies hide_from_window_list when
 * docking (49+ window API, or owned client on 48). No-op paths on X11. Leave
 * ShellService/Dock source free of this logic.
 */
export class WaylandLegacyWorkaround {
    constructor() {
        this.shell = null;
        this.client = null;
        this.pending = false;
        this.spawnTries = 0;
        this.watchId = 0;
        this.dockMode = true;
        this.dockModeWatchId = 0;
    }

    /**
     * Wrap shell + dock methods; call once from extension enable.
     */
    install(shell, dock) {
        var self = this;
        this.shell = shell;

        var origDisable = shell.disable.bind(shell);
        shell.disable = function() {
            self.teardown();
            origDisable();
        };

        var origRegister = shell.Register.bind(shell);
        shell.Register = function(role, handle) {
            if (self.pending && !self.client) {
                console.error('rooterm: Register ignored during handoff quit');
                return;
            }
            // App Bus.watch retries must not re-queue a role already stored —
            // Wayland bind is FIFO by map and will steal main for a dialog.
            if (self.shell.win[role]) {
                console.error('rooterm: Register skip already stored role=' + role);
                return;
            }
            origRegister(role, handle);
        };

        var origStoreRole = shell.storeRole.bind(shell);
        shell.storeRole = function(role, win) {
            if (self.needs(win)) {
                // Already handed off once — do not Quit/KILL loop on later maps.
                if (self.client || self.pending) {
                    console.error('rooterm: wayland bind unowned after handoff — ignore id='
                        + win.get_id());
                    return;
                }
                console.error('rooterm: wayland bind unowned — start handoff id='
                    + win.get_id());
                self.start();
                return;
            }
            origStoreRole(role, win);
            self.pending = false;
        };

        var origBind = shell.bindPendingWayland.bind(shell);
        shell.bindPendingWayland = function() {
            if (self.pending && !self.client) {
                return;
            }
            self.shell.waylandPending = self.shell.waylandPending.filter(function(p) {
                return !self.shell.win[p.role];
            });
            if (self.shell.waylandPending.length === 0) {
                return;
            }
            // Title-match roles — FIFO-by-map swaps Preferences/Connection on Wayland.
            var unbound = [];
            var actors = global.get_window_actors();
            for (var i = 0; i < actors.length; i++) {
                var win = actors[i].meta_window;
                if (!win || win.minimized || !self.shell.isRooTerm(win)) {
                    continue;
                }
                if (win === self.shell.win.main || win === self.shell.win.preferences) {
                    continue;
                }
                var rect = win.get_frame_rect();
                if (!rect || rect.width < 400 || rect.height < 400) {
                    continue;
                }
                unbound.push(win);
            }
            var left = [];
            for (var p = 0; p < self.shell.waylandPending.length; p++) {
                var pending = self.shell.waylandPending[p];
                var match = self.windowForRole(pending.role, unbound);
                if (!match) {
                    left.push(pending);
                    continue;
                }
                unbound = unbound.filter(function(w) {
                    return w !== match;
                });
                console.error('rooterm: wayland bind role=' + pending.role
                    + ' id=' + match.get_id()
                    + ' handle=' + pending.handle
                    + ' title=' + (match.get_title() || '')
                    + ' (title-match)');
                self.shell.storeRole(pending.role, match);
            }
            self.shell.waylandPending = left;
            if (left.length > 0 && unbound.length > 0) {
                origBind();
            }
        };

        // G48: Meta.Window has no show/hide_from_window_list — use WaylandClient
        // so minimize is allowed (otherwise finishHide resets opacity = bounce).
        var origFinishHide = shell.finishHide.bind(shell);
        shell.finishHide = function(role, actor) {
            var win = self.shell.win[role];
            if (win && self.client) {
                try {
                    if (self.client.owns_window(win)) {
                        self.client.show_in_window_list(win);
                    }
                } catch (e) {
                    console.error('rooterm: show_in_window_list: ' + e);
                }
            }
            origFinishHide(role, actor);
            if (win && win.minimized) {
                self.hideFromList(win);
            } else if (win) {
                console.error('rooterm: finishHide minimize failed role=' + role
                    + ' id=' + win.get_id());
            }
        };

        var origShow = shell.Show.bind(shell);
        shell.Show = function(role) {
            var win = self.shell.win[role];
            // Bracket: allow unminimize, then hide from list after slide-in.
            if (win && self.client) {
                try {
                    if (self.client.owns_window(win)) {
                        self.client.show_in_window_list(win);
                    }
                } catch (e) {
                    console.error('rooterm: show_in_window_list: ' + e);
                }
            }
            origShow(role);
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, function() {
                self.hideFromList(self.shell.win[role]);
                return GLib.SOURCE_REMOVE;
            });
        };

        // App Toggle is call_sync; DockMode call_sync on map deadlocks Show.
        // Cache DockMode async — never call_sync from the Shell main thread.
        dock.isDockMode = function() {
            self.refreshDockMode();
            return self.dockMode;
        };
        this.dockModeWatchId = Gio.DBus.session.signal_subscribe(
            DBUS_DEST, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
            DBUS_PATH, null, Gio.DBusSignalFlags.NONE,
            function(conn, sender, path, iface, signal, params) {
                var changed = params.get_child_value(1);
                var dock = changed.lookup_value('DockMode', null);
                if (!dock) {
                    return;
                }
                self.dockMode = dock.get_variant().get_boolean();
            }
        );
        this.refreshDockMode();

        var origDockMain = dock.dockMain.bind(dock);
        dock.dockMain = function(win) {
            origDockMain(win);
            self.hideFromList(win);
        };
    }

    refreshDockMode() {
        var self = this;
        Gio.DBus.session.call(
            DBUS_DEST, DBUS_PATH,
            'org.freedesktop.DBus.Properties', 'Get',
            new GLib.Variant('(ss)', [DBUS_IFACE, 'DockMode']),
            new GLib.VariantType('(v)'),
            Gio.DBusCallFlags.NONE,
            500,
            null,
            function(conn, res) {
                try {
                    var reply = Gio.DBus.session.call_finish(res);
                    self.dockMode = reply.get_child_value(0).get_variant().get_boolean();
                } catch (e) {
                    // Keep last cache; app may be mid call_sync Toggle.
                }
            }
        );
    }

    teardown() {
        this.client = null;
        this.pending = false;
        this.spawnTries = 0;
        if (this.watchId) {
            Gio.DBus.session.unwatch_name(this.watchId);
            this.watchId = 0;
        }
        if (this.dockModeWatchId) {
            Gio.DBus.session.signal_unsubscribe(this.dockModeWatchId);
            this.dockModeWatchId = 0;
        }
    }

    hideFromList(win) {
        // ShellService owns SkipTaskbar / 49+ Meta API; keep WaylandClient
        // path for GNOME 48 Wayland-owned windows only.
        if (!win) {
            return;
        }
        if (typeof win.hide_from_window_list === 'function') {
            return;
        }
        if (!this.client) {
            return;
        }
        try {
            if (this.client.owns_window(win)) {
                this.client.hide_from_window_list(win);
            }
        } catch (e) {
            console.error('rooterm: hide_from_window_list: ' + e);
        }
    }

    /**
     * Pick an unbound Meta window for a pending role by title.
     */
    windowForRole(role, windows) {
        for (var i = 0; i < windows.length; i++) {
            var title = (windows[i].get_title() || '').toLowerCase();
            if (role === 'preferences' && title.indexOf('preferences') !== -1) {
                return windows[i];
            }
            if (role === 'main' && title.indexOf('preferences') === -1) {
                return windows[i];
            }
        }
        return false;
    }

    needs(win) {
        if (!Meta.is_wayland_compositor()) {
            return false;
        }
        // GNOME 49+: Meta.Window.hide_from_window_list — no ownership needed.
        if (typeof win.hide_from_window_list === 'function') {
            return false;
        }
        if (!this.client) {
            return true;
        }
        try {
            return !this.client.owns_window(win);
        } catch (e) {
            console.error('rooterm: owns_window: ' + e);
            return true;
        }
    }

    start() {
        var self = this;
        if (this.pending) {
            return;
        }
        this.pending = true;
        this.spawnTries = 0;
        this.shell.win.main = false;
        this.shell.win.preferences = false;
        this.shell.waylandPending = [];
        console.error('rooterm: G48 Wayland handoff — Quit(true) then WaylandClient spawn');
        Gio.DBus.session.call(
            DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'Quit',
            new GLib.Variant('(b)', [true]),
            null, Gio.DBusCallFlags.NONE, 2000, null,
            function(conn, res) {
                try {
                    conn.call_finish(res);
                } catch (e) {
                    console.error('rooterm: handoff Quit(true): ' + e);
                }
                self.watchBusThenSpawn();
            }
        );
    }

    watchBusThenSpawn() {
        var self = this;
        if (this.watchId) {
            Gio.DBus.session.unwatch_name(this.watchId);
            this.watchId = 0;
        }
        this.watchId = Gio.DBus.session.watch_name(
            DBUS_DEST,
            Gio.BusNameWatcherFlags.NONE,
            function() {
            },
            function() {
                if (self.watchId) {
                    Gio.DBus.session.unwatch_name(self.watchId);
                    self.watchId = 0;
                }
                self.spawnOwned();
            }
        );
    }

    dbusNameOwned() {
        try {
            var reply = Gio.DBus.session.call_sync(
                'org.freedesktop.DBus',
                '/org/freedesktop/DBus',
                'org.freedesktop.DBus',
                'NameHasOwner',
                new GLib.Variant('(s)', [DBUS_DEST]),
                new GLib.VariantType('(b)'),
                Gio.DBusCallFlags.NONE,
                1000,
                null
            );
            return reply.get_child_value(0).get_boolean();
        } catch (e) {
            return false;
        }
    }

    spawnOwned() {
        var self = this;
        if (this.dbusNameOwned()) {
            this.spawnTries++;
            if (this.spawnTries > 25) {
                console.error('rooterm: handoff give up — D-Bus still owned');
                this.pending = false;
                return;
            }
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, function() {
                self.spawnOwned();
                return GLib.SOURCE_REMOVE;
            });
            return;
        }
        var bin = GLib.find_program_in_path('rooterm');
        if (!bin) {
            console.error('rooterm: handoff spawn — rooterm not in PATH');
            this.pending = false;
            return;
        }
        try {
            var launcher = Gio.SubprocessLauncher.new(Gio.SubprocessFlags.NONE);
            if (Meta.WaylandClient.new_subprocess) {
                this.client = Meta.WaylandClient.new_subprocess(
                    global.context, launcher, [bin]
                );
            } else if (Meta.WaylandClient.new.length === 1) {
                this.client = Meta.WaylandClient.new(launcher);
                this.client.spawnv(global.display, [bin]);
            } else {
                this.client = Meta.WaylandClient.new(global.context, launcher);
                this.client.spawnv(global.display, [bin]);
            }
            console.error('rooterm: handoff spawned ' + bin);
        } catch (e) {
            console.error('rooterm: handoff spawn failed: ' + e);
            this.client = null;
            this.pending = false;
        }
    }
}
