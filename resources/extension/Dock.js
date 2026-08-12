import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {DBUS_DEST, DBUS_PATH, DBUS_IFACE} from './Const.js';

/**
 * Underbar geometry for stored {@link ShellService.win}.main; dialog raise
 * for the stored preferences slot.
 */
export class Dock {
    constructor(shell) {
        this.shell = shell;
        this.dockTimeoutId = 0;
    }

    disable() {
        if (this.dockTimeoutId) {
            GLib.source_remove(this.dockTimeoutId);
            this.dockTimeoutId = 0;
        }
    }

    /**
     * (Re)dock main after a short delay (GTK may re-center after map / size).
     */
    scheduleDock() {
        var self = this;
        if (this.dockTimeoutId) {
            GLib.source_remove(this.dockTimeoutId);
            this.dockTimeoutId = 0;
        }
        this.dockTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, function() {
            self.dockTimeoutId = 0;
            self.dockStored();
            self.dockTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, function() {
                self.dockTimeoutId = 0;
                self.dockStored();
                return GLib.SOURCE_REMOVE;
            });
            return GLib.SOURCE_REMOVE;
        });
    }

    /**
     * Dock registered main; re-raise any open dialog slots.
     */
    dockStored() {
        if (!this.isDockMode()) {
            return;
        }
        var main = this.shell.win.main;
        if (main && !main.minimized) {
            this.dockMain(main);
        }
        this.raiseOpenDialogs();
    }

    /**
     * Map / Meta shown: only act on registered slots (no width classify).
     */
    dockWindow(win) {
        if (!win || win.minimized) {
            return;
        }
        if (win === this.shell.win.main) {
            if (this.isDockMode()) {
                this.dockMain(win);
                this.raiseOpenDialogs();
            }
            return;
        }
        if (win === this.shell.win.preferences) {
            this.raiseDialog(win);
            if (this.shell.win.main) {
                this.shell.win.main.unmake_above();
            }
        }
    }

    /**
     * True when the app reports underbar mode (D-Bus ``dock_mode``).
     */
    isDockMode() {
        try {
            var reply = Gio.DBus.session.call_sync(
                DBUS_DEST, DBUS_PATH,
                'org.freedesktop.DBus.Properties', 'Get',
                new GLib.Variant('(ss)', [DBUS_IFACE, 'dock_mode']),
                new GLib.VariantType('(v)'),
                Gio.DBusCallFlags.NONE,
                500,
                null
            );
            return reply.get_child_value(0).get_variant().get_boolean();
        } catch (e) {
            console.error('rooterm: dock_mode: ' + e);
            return false;
        }
    }

    raiseOpenDialogs() {
        if (this.shell.win.preferences && !this.shell.win.preferences.minimized) {
            this.raiseDialog(this.shell.win.preferences);
        }
    }

    /**
     * Preferences: centre once, keep above main.
     */
    raiseDialog(win) {
        if (this.shell.win.main) {
            this.shell.win.main.unmake_above();
        }
        if (!win.rootermCentered) {
            var mon = win.get_monitor();
            if (mon < 0) {
                mon = Main.layoutManager.primaryIndex;
            }
            var area = Main.layoutManager.getWorkAreaForMonitor(mon);
            var frame = win.get_frame_rect();
            win.rootermCentered = true;
            win.move_frame(
                true,
                area.x + Math.floor((area.width - frame.width) / 2),
                area.y + Math.floor((area.height - frame.height) / 2)
            );
        }
        win.make_above();
        win.raise();
        try {
            Main.activateWindow(win);
        } catch (e) {
            win.activate(global.get_current_time());
        }
    }

    /**
     * Main: pin under the panel; yield ``make_above`` while a dialog slot is open.
     */
    dockMain(win) {
        var self = this;
        var monitorIndex = win.get_monitor();
        if (monitorIndex < 0) {
            monitorIndex = Main.layoutManager.primaryIndex;
        }
        var workArea = Main.layoutManager.getWorkAreaForMonitor(monitorIndex);
        if (!workArea) {
            return;
        }
        var rect = win.get_frame_rect();
        var height = rect.height;
        var width = rect.width;
        var placement = 'centre';
        var fullscreen = false;
        try {
            var confPath = GLib.build_filenamev([
                GLib.get_home_dir(), '.config', 'rooterm', 'config.json',
            ]);
            var [, contents] = GLib.file_get_contents(confPath);
            var conf = JSON.parse(new TextDecoder().decode(contents));
            placement = conf.placement;
        } catch (e) {
            console.error('rooterm: layout config: ' + e);
        }
        try {
            var reply = Gio.DBus.session.call_sync(
                DBUS_DEST, DBUS_PATH,
                'org.freedesktop.DBus.Properties', 'Get',
                new GLib.Variant('(ss)', [DBUS_IFACE, 'fullscreen']),
                new GLib.VariantType('(v)'),
                Gio.DBusCallFlags.NONE,
                500,
                null
            );
            fullscreen = reply.get_child_value(0).get_variant().get_boolean();
        } catch (e) {
            console.error('rooterm: fullscreen: ' + e);
        }
        if (fullscreen) {
            width = workArea.width;
            height = workArea.height;
        }
        var x = workArea.x
            + (fullscreen ? 0
                : placement === 'centre' ? Math.floor((workArea.width - width) / 2)
                : placement === 'right' ? workArea.width - width : 0);
        var y = workArea.y;
        var already = Math.abs(rect.x - x) < 2 && Math.abs(rect.y - y) < 2
            && Math.abs(rect.width - width) < 2 && Math.abs(rect.height - height) < 2;
        if (!already) {
            if (win.rootermDocking) {
                return;
            }
            win.rootermDocking = true;
            win.unmaximize(Meta.MaximizeFlags.HORIZONTAL | Meta.MaximizeFlags.VERTICAL);
            win.move_frame(false, x, y);
            win.move_resize_frame(false, x, y, width, height);
            var after = win.get_frame_rect();
            if (Math.abs(after.y - y) > 2) {
                console.error('rooterm: dock wanted y=' + y
                    + ' but frame is y=' + after.y
                    + ' (was ' + rect.y + ') workArea.y=' + workArea.y);
            }
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, function() {
                win.rootermDocking = false;
                return GLib.SOURCE_REMOVE;
            });
        }
        if (!win.rootermDockHooked) {
            win.rootermDockHooked = true;
            win.connect('size-changed', function() {
                self.dockWindow(win);
            });
            win.connect('position-changed', function() {
                self.dockWindow(win);
            });
        }
        if (this.shell.win.preferences && !this.shell.win.preferences.minimized) {
            win.unmake_above();
            win.stick();
            return;
        }
        win.make_above();
        win.stick();
        try {
            Main.activateWindow(win);
        } catch (e) {
            win.activate(global.get_current_time());
        }
    }
}
