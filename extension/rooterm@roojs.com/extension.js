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
        this.settings = this.getSettings();
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
            if (self.settings) {
                var shortcuts = self.settings.get_strv('toggle');
                if (shortcuts && shortcuts.length > 0 && shortcuts[0]) {
                    key = shortcuts[0];
                }
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
                if (self.dockTimeoutId) {
                    GLib.source_remove(self.dockTimeoutId);
                }
                self.dockTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 80, function() {
                    self.dockTimeoutId = 0;
                    var actors = global.get_window_actors();
                    for (var i = 0; i < actors.length; i++) {
                        self.dockWindow(actors[i].meta_window);
                    }
                    return GLib.SOURCE_REMOVE;
                });
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
        this.settings = null;
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
        // Brief delay so Toggle show/map finishes before Mutter move.
        this.dockTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 80, function() {
            self.dockTimeoutId = 0;
            var actors = global.get_window_actors();
            for (var i = 0; i < actors.length; i++) {
                self.dockWindow(actors[i].meta_window);
            }
            return GLib.SOURCE_REMOVE;
        });
    }

    /**
     * If ``win`` is RooTerm, move it under the top panel and keep it above.
     */
    dockWindow(win) {
        if (!win || win.minimized) {
            return;
        }
        var match = false;
        try {
            match = win.get_gtk_application_id && win.get_gtk_application_id() === APP_ID;
        } catch (e) {
        }
        if (!match) {
            var cls = win.get_wm_class();
            var instance = win.get_wm_class_instance();
            match = (cls && cls.toLowerCase().indexOf('rooterm') !== -1)
                || (instance && instance.toLowerCase().indexOf('rooterm') !== -1);
        }
        if (!match) {
            return;
        }
        var monitor = Main.layoutManager.monitors[win.get_monitor()]
            || Main.layoutManager.primaryMonitor;
        if (!monitor) {
            return;
        }
        var rect = win.get_frame_rect();
        var height = rect.height > 0 ? rect.height : Math.floor(monitor.height * 60 / 100);
        try {
            win.unmaximize(Meta.MaximizeFlags.HORIZONTAL | Meta.MaximizeFlags.VERTICAL);
        } catch (e) {
        }
        try {
            win.make_above();
        } catch (e) {
        }
        try {
            win.stick();
        } catch (e) {
        }
        win.move_resize_frame(true, monitor.x,
            monitor.y + Main.layoutManager.panelBox.get_height(),
            monitor.width, height);
    }
}
