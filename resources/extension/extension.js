import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const DBUS_DEST = 'org.roojs.RooTerm.DBus';
const DBUS_PATH = '/org/roojs/RooTerm/DBus';
const DBUS_IFACE = 'org.roojs.RooTerm.DBus';
const APP_ID = 'org.roojs.rooterm';

const RooTermIndicator = GObject.registerClass(
class RooTermIndicator extends PanelMenu.Button {
    _init(extension) {
        super._init(0.0, 'RooTerm', false);
        this.extension = extension;

        this.add_child(new St.Icon({
            icon_name: 'utilities-terminal-symbolic',
            style_class: 'system-status-icon',
        }));

        var self = this;
        var prefsItem = new PopupMenu.PopupMenuItem('Preferences');
        prefsItem.connect('activate', function() {
            Gio.DBus.session.call(
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'Preferences',
                null, null, Gio.DBusCallFlags.NONE, 2000, null,
                self.extension.onDBusFinished.bind(self.extension, 'Preferences')
            );
        });
        this.menu.addMenuItem(prefsItem);

        var aboutItem = new PopupMenu.PopupMenuItem('About');
        aboutItem.connect('activate', function() {
            Gio.DBus.session.call(
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'About',
                null, null, Gio.DBusCallFlags.NONE, 2000, null,
                self.extension.onDBusFinished.bind(self.extension, 'About')
            );
        });
        this.menu.addMenuItem(aboutItem);

        var quitItem = new PopupMenu.PopupMenuItem('Quit');
        quitItem.connect('activate', function() {
            Gio.DBus.session.call(
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'Quit',
                null, null, Gio.DBusCallFlags.NONE, 2000, null,
                self.extension.onDBusFinished.bind(self.extension, 'Quit')
            );
        });
        this.menu.addMenuItem(quitItem);
    }

    vfunc_event(event) {
        if (!this.menu) {
            return Clutter.EVENT_PROPAGATE;
        }
        if (event.type() !== Clutter.EventType.TOUCH_BEGIN
                && event.type() !== Clutter.EventType.BUTTON_PRESS) {
            return Clutter.EVENT_PROPAGATE;
        }

        // Left click / touch → toggle; right click → menu
        if (event.type() === Clutter.EventType.TOUCH_BEGIN
                || event.get_button() === Clutter.BUTTON_PRIMARY) {
            Gio.DBus.session.call(
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'Toggle',
                null, null, Gio.DBusCallFlags.NONE, 2000, null,
                this.extension.onDBusFinished.bind(this.extension, 'Toggle')
            );
            return Clutter.EVENT_PROPAGATE;
        }
        if (event.get_button() === Clutter.BUTTON_SECONDARY) {
            this.menu.toggle();
        }
        return Clutter.EVENT_PROPAGATE;
    }
});

export default class RooTermExtension extends Extension {
    enable() {
        var self = this;
        this.windowCreatedId = 0;
        this.mapId = 0;
        this.shownSignalId = 0;
        this.dockTimeoutId = 0;

        this.indicator = new RooTermIndicator(this);

        if (Main.layoutManager && Main.layoutManager.uiGroup) {
            this.panelTooltip = new St.BoxLayout({
                style_class: 'rooterm-tooltip',
                visible: false,
                opacity: 0,
            });
            this.panelTooltipLabel = new St.Label({text: ''});
            this.panelTooltip.add_child(this.panelTooltipLabel);
            Main.layoutManager.uiGroup.add_child(this.panelTooltip);
        }

        this.indicator.connect('enter-event', function() {
            if (!self.panelTooltip || !self.indicator) {
                return;
            }
            var key = 'F12';
            try {
                var confPath = GLib.build_filenamev([
                    GLib.get_home_dir(), '.config', 'rooterm', 'connections.json',
                ]);
                var [, contents] = GLib.file_get_contents(confPath);
                var conf = JSON.parse(new TextDecoder().decode(contents));
                if (conf['toggle-key']) {
                    key = conf['toggle-key'];
                }
            } catch (e) {
                console.error('rooterm: toggle_key: ' + e);
            }
            self.panelTooltipLabel.text = key + ' / click — hide/show · right-click for Quit';
            var pos = self.indicator.get_transformed_position();
            var size = self.indicator.get_transformed_size();
            self.panelTooltip.set_position(pos[0], pos[1] + size[1] + 5);
            self.panelTooltip.opacity = 255;
            self.panelTooltip.visible = true;
        });
        this.indicator.connect('leave-event', function() {
            if (!self.panelTooltip) {
                return;
            }
            self.panelTooltip.visible = false;
            self.panelTooltip.opacity = 0;
        });

        Main.panel.addToStatusArea('rooterm', this.indicator, 1, 'right');
        this.indicator.visible = false;
        this.nameWatchId = Gio.DBus.session.watch_name(
            DBUS_DEST,
            Gio.BusNameWatcherFlags.NONE,
            function() {
                if (self.indicator) {
                    self.indicator.visible = true;
                }
                // Name can appear after first map/Shown — retry dock then.
                self.scheduleDock();
            },
            function() {
                if (self.panelTooltip) {
                    self.panelTooltip.visible = false;
                    self.panelTooltip.opacity = 0;
                }
                if (self.indicator) {
                    self.indicator.menu.close();
                    self.indicator.visible = false;
                }
            }
        );
        // Global toggle is a settings-daemon custom shortcut (rooterm --toggle).
        // Dock on map / Shown so media-keys path still pins under the panel.
        this.windowCreatedId = global.display.connect('window-created', function(display, window) {
            window.connect('shown', function() {
                self.dockWindow(window);
            });
        });
        this.mapId = global.window_manager.connect('map', function(wm, actor) {
            self.dockWindow(actor.meta_window);
        });
        this.shownSignalId = Gio.DBus.session.signal_subscribe(
            DBUS_DEST, DBUS_IFACE, 'Shown', DBUS_PATH, null,
            Gio.DBusSignalFlags.NONE,
            function() {
                self.scheduleDock();
            }
        );
    }

    disable() {
        if (this.dockTimeoutId) {
            GLib.source_remove(this.dockTimeoutId);
            this.dockTimeoutId = 0;
        }
        if (this.windowCreatedId) {
            global.display.disconnect(this.windowCreatedId);
            this.windowCreatedId = 0;
        }
        if (this.mapId) {
            global.window_manager.disconnect(this.mapId);
            this.mapId = 0;
        }
        if (this.shownSignalId) {
            Gio.DBus.session.signal_unsubscribe(this.shownSignalId);
            this.shownSignalId = 0;
        }
        if (this.nameWatchId) {
            Gio.DBus.session.unwatch_name(this.nameWatchId);
            this.nameWatchId = 0;
        }
        if (this.panelTooltip) {
            this.panelTooltip.destroy();
            this.panelTooltip = null;
            this.panelTooltipLabel = null;
        }
        if (this.indicator) {
            this.indicator.destroy();
            this.indicator = null;
        }
    }

    onDBusFinished(method, conn, result) {
        var self = this;
        try {
            conn.call_finish(result);
        } catch (e) {
            if (method !== 'Toggle') {
                return;
            }
            try {
                GLib.spawn_command_line_async('rooterm --toggle');
            } catch (spawnErr) {
                console.error('rooterm: spawn failed: ' + spawnErr);
                return;
            }
        }
        if (method !== 'Toggle') {
            return;
        }
        if (this.dockTimeoutId) {
            GLib.source_remove(this.dockTimeoutId);
        }
        this.scheduleDock();
    }

    /**
     * Dock all RooTerm windows after a short delay (GTK may re-center after map).
     */
    scheduleDock() {
        var self = this;
        if (this.dockTimeoutId) {
            GLib.source_remove(this.dockTimeoutId);
        }
        this.dockTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, function() {
            self.dockTimeoutId = 0;
            self.dockAll();
            // Second pass — set_default_size / present often recenters after the first move.
            self.dockTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, function() {
                self.dockTimeoutId = 0;
                self.dockAll();
                return GLib.SOURCE_REMOVE;
            });
            return GLib.SOURCE_REMOVE;
        });
    }

    dockAll() {
        var prefs = null;
        var actors = global.get_window_actors();
        for (var i = 0; i < actors.length; i++) {
            var win = actors[i].meta_window;
            this.dockWindow(win);
            if (!win) {
                continue;
            }
            var title = win.get_title() || '';
            if ((win.decorated && win.get_gtk_application_id
                    && win.get_gtk_application_id() === APP_ID)
                    || title === 'Preferences'
                    || title === 'Connection') {
                prefs = win;
            }
        }
        // Drop-down re-dock may have run last — keep Preferences / Connection on top.
        if (!prefs) {
            return;
        }
        prefs.make_above();
        prefs.raise();
        try {
            Main.activateWindow(prefs);
        } catch (e) {
            prefs.activate(global.get_current_time());
        }
    }

    /**
     * True when the app reports underbar drop-down mode (D-Bus ``DockMode``).
     */
    isDockMode() {
        try {
            // GJS: pack tuples from an array; read ``(v)`` via get_variant().
            // deep_unpack() yields ``{}`` for booleans here — never use it for DockMode.
            var reply = Gio.DBus.session.call_sync(
                DBUS_DEST, DBUS_PATH,
                'org.freedesktop.DBus.Properties', 'Get',
                new GLib.Variant('(ss)', [DBUS_IFACE, 'DockMode']),
                new GLib.VariantType('(v)'),
                Gio.DBusCallFlags.NONE,
                500,
                null
            );
            return reply.get_child_value(0).get_variant().get_boolean();
        } catch (e) {
            console.error('rooterm: DockMode: ' + e);
            return false;
        }
    }

    /**
     * Drop-down: move under the panel and keep above.
     * Preferences / Connection (decorated): raise above; drop-down loses ``make_above``
     * while that window is open so stacking can win.
     */
    dockWindow(win) {
        if (!win || win.minimized) {
            return;
        }
        var match = win.get_gtk_application_id
            && win.get_gtk_application_id() === APP_ID;
        if (!match) {
            var cls = win.get_wm_class();
            var instance = win.get_wm_class_instance();
            match = (cls && cls.toLowerCase().indexOf('rooterm') !== -1)
                || (instance && instance.toLowerCase().indexOf('rooterm') !== -1);
        }
        if (!match) {
            return;
        }
        if (!this.isDockMode()) {
            return;
        }
        var self = this;
        var decorated = !!win.decorated;
        var title = win.get_title() || '';
        // Decorated = Preferences / Connection (drop-down is undecorated). Title helps on Wayland.
        if (decorated || title === 'Preferences' || title === 'Connection') {
            var actors = global.get_window_actors();
            for (var i = 0; i < actors.length; i++) {
                var other = actors[i].meta_window;
                if (!other || other === win || other.minimized || other.decorated) {
                    continue;
                }
                var otherMatch = other.get_gtk_application_id
                    && other.get_gtk_application_id() === APP_ID;
                if (!otherMatch) {
                    var ocls = other.get_wm_class();
                    var oinst = other.get_wm_class_instance();
                    otherMatch = (ocls && ocls.toLowerCase().indexOf('rooterm') !== -1)
                        || (oinst && oinst.toLowerCase().indexOf('rooterm') !== -1);
                }
                if (!otherMatch) {
                    continue;
                }
                // Both were ``make_above`` — drop-down re-asserting above keeps covering prefs.
                other.unmake_above();
            }
            // First map: centre on the work area (GTK parks new windows at the top).
            if (!win.rootermCentered) {
                var mon = win.get_monitor();
                if (mon < 0) {
                    mon = Main.layoutManager.primaryIndex;
                }
                var area = Main.layoutManager.getWorkAreaForMonitor(mon);
                var frame = win.get_frame_rect();
                if (area && frame.width >= 100 && frame.height >= 100) {
                    win.rootermCentered = true;
                    win.move_frame(
                        true,
                        area.x + Math.floor((area.width - frame.width) / 2),
                        area.y + Math.floor((area.height - frame.height) / 2)
                    );
                }
            }
            win.make_above();
            win.raise();
            if (!win.rootermPrefsHooked) {
                win.rootermPrefsHooked = true;
                win.connect('unmanaged', function() {
                    self.scheduleDock();
                });
            }
            try {
                Main.activateWindow(win);
            } catch (e) {
                win.activate(global.get_current_time());
            }
            return;
        }

        var monitorIndex = win.get_monitor();
        if (monitorIndex < 0) {
            monitorIndex = Main.layoutManager.primaryIndex;
        }
        var workArea = Main.layoutManager.getWorkAreaForMonitor(monitorIndex);
        if (!workArea) {
            return;
        }
        var rect = win.get_frame_rect();
        // Skip GTK's transient 1×1 / unrealized surfaces.
        if (rect.width < 100 || rect.height < 100) {
            return;
        }
        var height = rect.height;
        var width = rect.width;
        var placement = 'centre';
        try {
            var confPath = GLib.build_filenamev([GLib.get_home_dir(), '.config', 'rooterm', 'connections.json']);
            var [, contents] = GLib.file_get_contents(confPath);
            var conf = JSON.parse(new TextDecoder().decode(contents));
            placement = conf.placement;
        } catch (e) {
            console.error('rooterm: layout config: ' + e);
        }
        var x = workArea.x
            + (placement === 'centre' ? Math.floor((workArea.width - width) / 2)
                : placement === 'right' ? workArea.width - width : 0);
        // Work area top — not panelBox.get_height() (can disagree with real panel).
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
        // Preferences / Connection open: keep drop-down visible but not ``above``.
        var actors = global.get_window_actors();
        for (var i = 0; i < actors.length; i++) {
            var other = actors[i].meta_window;
            if (!other || other.minimized) {
                continue;
            }
            var otherTitle = other.get_title() || '';
            if (!other.decorated
                    && otherTitle !== 'Preferences'
                    && otherTitle !== 'Connection') {
                continue;
            }
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
