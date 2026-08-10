import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {APP_ID, DBUS_DEST, DBUS_IFACE, DBUS_PATH, PREFS_DBUS_DEST, PREFS_DBUS_PATH, SHELL_DEST, SHELL_PATH} from './Const.js';

/**
 * Session bus org.roojs.RooTerm.Shell — register / show / hide / toggle / exited
 * and Meta window slots for main / preferences.
 *
 * Hide is Meta minimize (keeps slots alive). Main slides then minimizes.
 * skip_taskbar is cleared briefly around minimize (GNOME 48: app D-Bus
 * skip_taskbar; 49+: Meta show/hide_from_window_list) so overview stays clear
 * without blocking minimize. skip_taskbar is always async (never call_sync).
 */
export class ShellService {
    constructor(extensionPath) {
        this.extensionPath = extensionPath;
        this.win = {
            main: false,
            preferences: false,
        };
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
        this.win.main = false;
        this.win.preferences = false;
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
    register(role, handle) {
        console.error('rooterm: register role=' + role + ' handle=' + handle);
        if (handle.indexOf('wayland:') === 0) {
            this.waylandPending.push({
                role: role,
                handle: handle.substring('wayland:'.length),
            });
            this.bindPendingWayland();
            return;
        }
        if (handle.indexOf('x11:') !== 0) {
            console.error('rooterm: register bad handle prefix');
            return;
        }
        var win = this.resolveX11(handle.substring('x11:'.length));
        if (!win) {
            console.error('rooterm: register x11 resolve failed role=' + role);
            return;
        }
        this.storeRole(role, win);
    }

    /**
     * App D-Bus skip_taskbar: main vs preferences process.
     */
    skipTaskbar(role, skip, done) {
        var dest = DBUS_DEST;
        var path = DBUS_PATH;
        if (role === 'preferences') {
            dest = PREFS_DBUS_DEST;
            path = PREFS_DBUS_PATH;
        }
        Gio.DBus.session.call(
            dest, path, DBUS_IFACE, 'skip_taskbar',
            new GLib.Variant('(sb)', [role, skip]),
            null, Gio.DBusCallFlags.NONE, -1, null,
            function(conn, res) {
                try {
                    Gio.DBus.session.call_finish(res);
                } catch (e) {
                    console.error('rooterm: skip_taskbar ' + skip
                        + ' role=' + role + ': ' + e);
                }
                if (done) {
                    done();
                }
            }
        );
    }

    show(role) {
        var self = this;
        if (!this.win[role]) {
            console.error('rooterm: show missing role=' + role);
            return;
        }
        this.win[role].rootermHiding = false;
        this.win[role].rootermReadyToMinimize = false;
        if (this.win[role].rootermBracketId) {
            GLib.source_remove(this.win[role].rootermBracketId);
            this.win[role].rootermBracketId = 0;
        }
        if (this.win[role].minimized) {
            var showActor = this.win[role].get_compositor_private();
            if (showActor && Main.wm && typeof Main.wm.skipNextEffect === 'function') {
                Main.wm.skipNextEffect(showActor);
            }
            this.win[role].unminimize();
        }
        // Restore skip_taskbar after show (async).
        this.skipTaskbar(role, true, function() {
            if (self.win[role]
                    && typeof self.win[role].hide_from_window_list === 'function') {
                self.win[role].hide_from_window_list();
            }
        });
        if (role !== 'preferences') {
            var actor = this.win[role].get_compositor_private();
            if (actor) {
                actor.remove_all_transitions();
                actor.opacity = 255;
                actor.show();
                var height = Math.max(this.win[role].get_frame_rect().height, 1);
                actor.translation_y = -height;
                this.showMain();
                actor.ease({
                    translation_y: 0,
                    duration: 180,
                    mode: Clutter.AnimationMode.EASE_OUT_CUBIC,
                    onStopped: function() {
                        actor.translation_y = 0;
                        actor.opacity = 255;
                    },
                });
                return;
            }
            this.showMain();
            return;
        }
        if (this.win.main) {
            this.win.main.unmake_above();
        }
        if (!this.win[role].rootermCentered) {
            var mon = this.win[role].get_monitor();
            if (mon < 0) {
                mon = Main.layoutManager.primaryIndex;
            }
            var area = Main.layoutManager.getWorkAreaForMonitor(mon);
            var frame = this.win[role].get_frame_rect();
            this.win[role].rootermCentered = true;
            this.win[role].move_frame(
                true,
                area.x + Math.floor((area.width - frame.width) / 2),
                area.y + Math.floor((area.height - frame.height) / 2)
            );
        }
        this.win[role].make_above();
        this.win[role].raise();
        try {
            Main.activateWindow(this.win[role]);
        } catch (e) {
            this.win[role].activate(global.get_current_time());
        }
        console.error('rooterm: show role=' + role + ' id=' + this.win[role].get_id()
            + ' minimized=' + this.win[role].minimized);
    }

    /**
     * Show main underbar; yield stacking if preferences is open.
     */
    showMain() {
        var front = (this.win.preferences && !this.win.preferences.minimized)
            ? this.win.preferences
            : false;
        this.win.main.make_above();
        this.win.main.raise();
        if (front) {
            this.win.main.unmake_above();
            front.make_above();
            front.raise();
            try {
                Main.activateWindow(front);
            } catch (e) {
                front.activate(global.get_current_time());
            }
            console.error('rooterm: show role=main id=' + this.win.main.get_id()
                + ' minimized=' + this.win.main.minimized + ' under-dialog');
            return;
        }
        try {
            Main.activateWindow(this.win.main);
        } catch (e) {
            this.win.main.activate(global.get_current_time());
        }
        console.error('rooterm: show role=main id=' + this.win.main.get_id()
            + ' minimized=' + this.win.main.minimized);
    }

    hide(role) {
        var self = this;
        if (!this.win[role]) {
            console.error('rooterm: hide missing role=' + role);
            return;
        }
        var actor = this.win[role].get_compositor_private();
        // Main: slide off-screen first, then re-enter to minimize.
        if (role !== 'preferences'
                && actor && !this.win[role].rootermReadyToMinimize) {
            this.win[role].rootermHiding = true;
            actor.remove_all_transitions();
            var height = Math.max(this.win[role].get_frame_rect().height, 1);
            actor.ease({
                translation_y: -height,
                duration: 180,
                mode: Clutter.AnimationMode.EASE_IN_CUBIC,
                onStopped: function() {
                    if (!self.win[role] || !self.win[role].rootermHiding) {
                        return;
                    }
                    self.win[role].rootermHiding = false;
                    actor.opacity = 0;
                    self.win[role].rootermReadyToMinimize = true;
                    self.hide(role);
                },
            });
            return;
        }
        this.win[role].rootermReadyToMinimize = false;
        if (this.win[role].rootermBracketId) {
            GLib.source_remove(this.win[role].rootermBracketId);
            this.win[role].rootermBracketId = 0;
        }
        // Clear skip_taskbar → idle → minimize → restore skip (async only).
        this.skipTaskbar(role, false, function() {
            if (!self.win[role]) {
                return;
            }
            if (typeof self.win[role].show_in_window_list === 'function') {
                self.win[role].show_in_window_list();
            }
            self.win[role].rootermBracketId = GLib.timeout_add(
                GLib.PRIORITY_DEFAULT, 50, function() {
                    self.finishHide(role, actor);
                    return GLib.SOURCE_REMOVE;
                }
            );
        });
    }

    /**
     * After skip_taskbar is cleared: minimize (no WM effect), restore skip,
     * and put main back above when preferences is hidden.
     */
    finishHide(role, actor) {
        var self = this;
        if (!this.win[role]) {
            return;
        }
        this.win[role].rootermBracketId = 0;
        if (actor && Main.wm && typeof Main.wm.skipNextEffect === 'function') {
            Main.wm.skipNextEffect(actor);
        }
        this.win[role].minimize();
        if (actor) {
            actor.translation_y = 0;
            actor.opacity = 255;
        }
        this.skipTaskbar(role, true, function() {
            if (self.win[role] && typeof self.win[role].hide_from_window_list === 'function') {
                self.win[role].hide_from_window_list();
            }
        });

                           console.error('rooterm: hide role=' + role + ' id=' + this.win[role].get_id()
            + ' minimized=' + this.win[role].minimized);
        if (role !== 'preferences') {
            return;
        }
        if ((this.win.preferences && !this.win.preferences.minimized)
                || !this.win.main || this.win.main.minimized) {
            return;
        }
        this.win.main.make_above();
    }

    toggle(role) {
        if (!this.win[role]) {
            console.error('rooterm: toggle missing role=' + role);
            return;
        }
        if (this.win[role].minimized || this.win[role].rootermHiding) {
            this.show(role);
            return;
        }
        this.hide(role);
    }

    /**
     * App process left — drop only that app's roles (main vs preferences).
     */
    exited(appId) {
        console.error('rooterm: exited app_id=' + appId);
        if (appId === 'org.roojs.rooterm') {
            this.win.main = false;
            this.waylandPending = this.waylandPending.filter(function(p) {
                return p.role !== 'main';
            });
            return;
        }
        if (appId === 'org.roojs.rooterm.preferences') {
            this.win.preferences = false;
            this.waylandPending = this.waylandPending.filter(function(p) {
                return p.role !== 'preferences';
            });
            return;
        }
        console.error('rooterm: exited unknown app_id=' + appId);
    }

    storeRole(role, win) {
        var self = this;
        if (!(role in this.win)) {
            console.error('rooterm: storeRole bad role=' + role);
            return;
        }
        this.win[role] = win;
        console.error('rooterm: stored role=' + role + ' id=' + this.win[role].get_id()
            + ' title=' + (this.win[role].get_title() || ''));
        this.skipTaskbar(role, true, function() {
            if (self.win[role] && typeof self.win[role].hide_from_window_list === 'function') {
                self.win[role].hide_from_window_list();
            }
        });
        if (!this.win[role].rootermSlotHooked) {
            this.win[role].rootermSlotHooked = true;
            this.win[role].connect('unmanaged', function() {
                if (self.win[role] === win) {
                    self.win[role] = false;
                }
                console.error('rooterm: unmanaged cleared slot id=' + win.get_id());
            });
        }
    }

    resolveX11(hex) {
        var want = parseInt(hex, 16);
        if (isNaN(want)) {
            console.error('rooterm: resolveX11 bad hex=' + hex);
            return false;
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
        return false;
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
            if (win === this.win.main || win === this.win.preferences) {
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
