import Gio from 'gi://Gio';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {APP_ID, SHELL_DEST, SHELL_PATH} from './Const.js';

/**
 * Session bus org.roojs.RooTerm.Shell — Register / Show / Hide / Toggle
 * and Meta window slots for main / preferences / connection.
 */
export class ShellService {
    constructor(extensionPath) {
        this.extensionPath = extensionPath;
        this.mainWin = null;
        this.prefsWin = null;
        this.connectionWin = null;
        this.waylandPending = [];
        this.export = null;
        this.nameId = 0;
    }

    enable() {
        var file = Gio.File.new_for_path(this.extensionPath + '/ShellIface.xml');
        var [, bytes] = file.load_contents(null);
        var xml = new TextDecoder().decode(bytes);
        this.export = Gio.DBusExportedObject.wrapJSObject(xml, this);
        this.export.export(Gio.DBus.session, SHELL_PATH);
        this.nameId = Gio.DBus.session.own_name(
            SHELL_DEST,
            Gio.BusNameOwnerFlags.NONE,
            function() {
                console.error('rooterm: Shell bus acquired');
            },
            function() {
                console.error('rooterm: Shell bus lost');
            }
        );
    }

    disable() {
        this.mainWin = null;
        this.prefsWin = null;
        this.connectionWin = null;
        this.waylandPending = [];
        if (this.nameId) {
            Gio.DBus.session.unown_name(this.nameId);
            this.nameId = 0;
        }
        if (this.export) {
            this.export.unexport();
            this.export = null;
        }
    }

    /**
     * Phase 0: portal-style handle → Meta slot.
     * x11:HEX via get_description(); wayland: queued until next unbound RooTerm map
     * (Meta GJS has no xdg-foreign handle lookup).
     */
    Register(role, handle) {
        console.error('rooterm: Register role=' + role + ' handle=' + handle);
        if (handle.indexOf('wayland:') === 0) {
            this.waylandPending.push({
                role: role,
                handle: handle.substring('wayland:'.length),
            });
            this.bindPendingWayland();
            return;
        }
        if (handle.indexOf('x11:') !== 0) {
            console.error('rooterm: Register bad handle prefix');
            return;
        }
        var win = this.resolveX11(handle.substring('x11:'.length));
        if (!win) {
            console.error('rooterm: Register x11 resolve failed role=' + role);
            return;
        }
        this.storeRole(role, win);
    }

    Show(role) {
        var win = this.winForRole(role);
        if (!win) {
            console.error('rooterm: Show missing role=' + role);
            return;
        }
        if (win.minimized) {
            win.unminimize();
        }
        if (role !== 'preferences' && role !== 'connection') {
            this.showMain(win);
            return;
        }
        if (this.mainWin) {
            this.mainWin.unmake_above();
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
        console.error('rooterm: Show role=' + role + ' id=' + win.get_id()
            + ' minimized=' + win.minimized);
    }

    /**
     * Show main underbar; yield stacking if prefs/connection are open.
     */
    showMain(win) {
        var front = (this.connectionWin && !this.connectionWin.minimized)
            ? this.connectionWin
            : (this.prefsWin && !this.prefsWin.minimized)
                ? this.prefsWin
                : false;
        // Main first, then dialog on top (keep terminal out of focus).
        win.make_above();
        win.raise();
        if (front) {
            win.unmake_above();
            front.make_above();
            front.raise();
            try {
                Main.activateWindow(front);
            } catch (e) {
                front.activate(global.get_current_time());
            }
            console.error('rooterm: Show role=main id=' + win.get_id()
                + ' minimized=' + win.minimized + ' under-dialog');
            return;
        }
        try {
            Main.activateWindow(win);
        } catch (e) {
            win.activate(global.get_current_time());
        }
        console.error('rooterm: Show role=main id=' + win.get_id()
            + ' minimized=' + win.minimized);
    }

    Hide(role) {
        var win = this.winForRole(role);
        if (!win) {
            console.error('rooterm: Hide missing role=' + role);
            return;
        }
        win.minimize();
        console.error('rooterm: Hide role=' + role + ' id=' + win.get_id()
            + ' minimized=' + win.minimized);
        if (role !== 'preferences' && role !== 'connection') {
            return;
        }
        if ((this.prefsWin && !this.prefsWin.minimized)
                || (this.connectionWin && !this.connectionWin.minimized)
                || !this.mainWin || this.mainWin.minimized) {
            return;
        }
        this.mainWin.make_above();
    }

    Toggle(role) {
        var win = this.winForRole(role);
        if (!win) {
            console.error('rooterm: Toggle missing role=' + role);
            return;
        }
        if (win.minimized) {
            this.Show(role);
            return;
        }
        this.Hide(role);
    }

    winForRole(role) {
        if (role === 'main') {
            return this.mainWin;
        }
        if (role === 'preferences') {
            return this.prefsWin;
        }
        if (role === 'connection') {
            return this.connectionWin;
        }
        return null;
    }

    storeRole(role, win) {
        var self = this;
        if (role === 'main') {
            this.mainWin = win;
        } else if (role === 'preferences') {
            this.prefsWin = win;
        } else if (role === 'connection') {
            this.connectionWin = win;
        } else {
            console.error('rooterm: storeRole bad role=' + role);
            return;
        }
        console.error('rooterm: stored role=' + role + ' id=' + win.get_id()
            + ' title=' + (win.get_title() || ''));
        if (!win.rootermSlotHooked) {
            win.rootermSlotHooked = true;
            win.connect('unmanaged', function() {
                if (self.mainWin === win) {
                    self.mainWin = null;
                }
                if (self.prefsWin === win) {
                    self.prefsWin = null;
                }
                if (self.connectionWin === win) {
                    self.connectionWin = null;
                }
                console.error('rooterm: unmanaged cleared slot id=' + win.get_id());
            });
        }
    }

    resolveX11(hex) {
        var want = parseInt(hex, 16);
        if (isNaN(want)) {
            console.error('rooterm: resolveX11 bad hex=' + hex);
            return null;
        }
        var actors = global.get_window_actors();
        for (var i = 0; i < actors.length; i++) {
            var win = actors[i].meta_window;
            if (!win) {
                continue;
            }
            var desc = win.get_description();
            if (desc && desc.indexOf('0x') === 0 && parseInt(desc, 16) === want) {
                return win;
            }
        }
        return null;
    }

    isRooTerm(win) {
        if (win.get_gtk_application_id && win.get_gtk_application_id() === APP_ID) {
            return true;
        }
        var cls = win.get_wm_class();
        var instance = win.get_wm_class_instance();
        return (cls && cls.toLowerCase().indexOf('rooterm') !== -1)
            || (instance && instance.toLowerCase().indexOf('rooterm') !== -1);
    }

    bindPendingWayland() {
        if (this.waylandPending.length === 0) {
            return;
        }
        var actors = global.get_window_actors();
        for (var i = 0; i < actors.length; i++) {
            if (this.waylandPending.length === 0) {
                return;
            }
            var win = actors[i].meta_window;
            if (!win || win.minimized || !this.isRooTerm(win)) {
                continue;
            }
            if (win === this.mainWin || win === this.prefsWin || win === this.connectionWin) {
                continue;
            }
            // Skip tiny surfaces (GTK map noise) so they do not steal pending roles.
            var rect = win.get_frame_rect();
            if (!rect || rect.width < 400 || rect.height < 400) {
                continue;
            }
            var pending = this.waylandPending.shift();
            console.error('rooterm: wayland bind role=' + pending.role
                + ' id=' + win.get_id()
                + ' handle=' + pending.handle
                + ' title=' + (win.get_title() || ''));
            this.storeRole(pending.role, win);
        }
    }
}
