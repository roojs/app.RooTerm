import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';

import {DBUS_DEST, DBUS_PATH, DBUS_IFACE} from './Const.js';

/**
 * GNOME 48 Wayland duct-tape only — monkey-patches ShellService / Dock.
 *
 * Mutter only allows hide_from_window_list for processes spawned via
 * Meta.WaylandClient. On first unowned storeRole, Quit and respawn through
 * WaylandClient. Also applies hide_from_window_list when docking (49+ window
 * API, or owned client on 48). No-op paths on X11. Leave ShellService/Dock
 * source free of this logic.
 */
export class WaylandLegacyWorkaround {
    constructor() {
        this.shell = null;
        this.client = null;
        this.pending = false;
        this.spawnTries = 0;
        this.watchId = 0;
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
            origRegister(role, handle);
        };

        var origStoreRole = shell.storeRole.bind(shell);
        shell.storeRole = function(role, win) {
            if (self.needs(win)) {
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
            origBind();
        };

        var origDockMain = dock.dockMain.bind(dock);
        dock.dockMain = function(win) {
            origDockMain(win);
            self.hideFromList(win);
        };
    }

    teardown() {
        this.client = null;
        this.pending = false;
        this.spawnTries = 0;
        if (this.watchId) {
            Gio.DBus.session.unwatch_name(this.watchId);
            this.watchId = 0;
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
        this.shell.win.connection = false;
        this.shell.waylandPending = [];
        console.error('rooterm: G48 Wayland handoff — Quit then WaylandClient spawn');
        Gio.DBus.session.call(
            DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'Quit',
            null, null, Gio.DBusCallFlags.NONE, 2000, null,
            function(conn, res) {
                try {
                    conn.call_finish(res);
                } catch (e) {
                    console.error('rooterm: handoff Quit: ' + e);
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
