import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
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

export default class RooTermExtension extends Extension {
    enable() {
        var self = this;
        this.settings = this.getSettings();
        this.keybindingNames = [];

        this.indicator = new PanelMenu.Button(0.0, 'RooTerm', false);
        this.indicator.add_child(new St.Icon({
            icon_name: 'utilities-terminal-symbolic',
            style_class: 'system-status-icon',
        }));

        var toggleItem = new PopupMenu.PopupMenuItem('Toggle');
        toggleItem.connect('activate', function() {
            Gio.DBus.session.call(
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'Toggle',
                null, null, Gio.DBusCallFlags.NONE, 2000, null,
                self.onDBusFinished.bind(self, 'Toggle')
            );
        });
        this.indicator.menu.addMenuItem(toggleItem);

        var quitItem = new PopupMenu.PopupMenuItem('Quit');
        quitItem.connect('activate', function() {
            Gio.DBus.session.call(
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'Quit',
                null, null, Gio.DBusCallFlags.NONE, 2000, null,
                self.onDBusFinished.bind(self, 'Quit')
            );
        });
        this.indicator.menu.addMenuItem(quitItem);

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
                if (shortcuts && shortcuts.length > 0) {
                    key = shortcuts[0];
                }
            }
            self.panelTooltipLabel.text = key + ' — hide/show · use rooterm --toggle-key to change';
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
        this.registerKeybindings();
        this.settings.connect('changed::toggle', function() {
            self.registerKeybindings();
        });
    }

    disable() {
        for (var i = 0; i < this.keybindingNames.length; i++) {
            Main.wm.removeKeybinding(this.keybindingNames[i]);
        }
        this.keybindingNames = [];
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

    registerKeybindings() {
        for (var i = 0; i < this.keybindingNames.length; i++) {
            Main.wm.removeKeybinding(this.keybindingNames[i]);
        }
        this.keybindingNames = [];
        if (!this.settings) {
            return;
        }
        var shortcuts = this.settings.get_strv('toggle');
        if (!shortcuts || shortcuts.length === 0) {
            return;
        }
        var self = this;
        Main.wm.addKeybinding('toggle', this.settings, Meta.KeyBindingFlags.NONE, Shell.ActionMode.ALL,
            function() {
                Gio.DBus.session.call(
                    DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'Toggle',
                    null, null, Gio.DBusCallFlags.NONE, 2000, null,
                    self.onDBusFinished.bind(self, 'Toggle')
                );
            });
        this.keybindingNames.push('toggle');
    }

    onDBusFinished(method, conn, result) {
        try {
            conn.call_finish(result);
            return;
        } catch (e) {
            if (method !== 'Toggle') {
                return;
            }
        }
        try {
            GLib.spawn_command_line_async('rooterm --toggle');
        } catch (spawnErr) {
            console.error('rooterm: spawn failed: ' + spawnErr);
        }
    }
}
