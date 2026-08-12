import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {DBUS_DEST, DBUS_PATH, DBUS_IFACE} from './Const.js';
import {Dock} from './Dock.js';
import {Indicator} from './Indicator.js';
import {ShellService} from './ShellService.js';
import {WaylandLegacyWorkaround} from './WaylandLegacyWorkaround.js';

export default class RooTermExtension extends Extension {
    enable() {
        var self = this;
        this.windowCreatedId = 0;
        this.mapId = 0;
        this.redockSignalId = 0;

        this.shell = new ShellService(this.path);
        this.shell.enable();
        this.dock = new Dock(this.shell);
        // GNOME 48 Wayland Quit+respawn / hide-from-overview — patches only.
        new WaylandLegacyWorkaround().install(this.shell, this.dock);

        this.indicator = new Indicator(this);

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
                    GLib.get_home_dir(), '.config', 'rooterm', 'config.json',
                ]);
                var [, contents] = GLib.file_get_contents(confPath);
                var conf = JSON.parse(new TextDecoder().decode(contents));
                if (conf['key-toggle']) {
                    key = conf['key-toggle'];
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

        Main.panel.addToStatusArea('rooterm', this.indicator, 0, 'right');
        this.indicator.visible = false;
        this.nameWatchId = Gio.DBus.session.watch_name(
            DBUS_DEST,
            Gio.BusNameWatcherFlags.NONE,
            function() {
                if (self.indicator) {
                    self.indicator.visible = true;
                }
                // Name can appear after first map/Redock — retry dock then.
                self.dock.scheduleDock();
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
                if (self.shell) {
                    self.shell.exited('org.roojs.rooterm');
                }
            }
        );
        // Global toggle is a settings-daemon custom shortcut (rooterm --toggle).
        // Dock on map / Redock so media-keys path still pins under the panel.
        this.windowCreatedId = global.display.connect('window-created', function(display, window) {
            window.connect('shown', function() {
                self.shell.bindPendingWayland();
                self.dock.dockWindow(window);
            });
        });
        this.mapId = global.window_manager.connect('map', function(wm, actor) {
            self.shell.bindPendingWayland();
            self.dock.dockWindow(actor.meta_window);
        });
        this.redockSignalId = Gio.DBus.session.signal_subscribe(
            DBUS_DEST, DBUS_IFACE, 'redock', DBUS_PATH, null,
            Gio.DBusSignalFlags.NONE,
            function(conn, sender, objectPath, ifaceName, signalName, params) {
                self.dock.scheduleDock(params.get_child_value(0).get_boolean());
            }
        );
    }

    disable() {
        if (this.windowCreatedId) {
            global.display.disconnect(this.windowCreatedId);
            this.windowCreatedId = 0;
        }
        if (this.mapId) {
            global.window_manager.disconnect(this.mapId);
            this.mapId = 0;
        }
        if (this.redockSignalId) {
            Gio.DBus.session.signal_unsubscribe(this.redockSignalId);
            this.redockSignalId = 0;
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
        if (this.dock) {
            this.dock.disable();
            this.dock = null;
        }
        if (this.shell) {
            this.shell.disable();
            this.shell = null;
        }
    }

    onDBusFinished(method, conn, result) {
        try {
            conn.call_finish(result);
        } catch (e) {
            if (method !== 'toggle') {
                return;
            }
            // Last resort if D-Bus Toggle failed (app not on bus yet).
            try {
                GLib.spawn_command_line_async('rooterm --toggle');
            } catch (spawnErr) {
                console.error('rooterm: spawn failed: ' + spawnErr);
                return;
            }
        }
        if (method !== 'toggle') {
            return;
        }
        this.dock.scheduleDock();
    }
}
