import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import {DBUS_DEST, DBUS_PATH, DBUS_IFACE} from './Const.js';

export const Indicator = GObject.registerClass(
class Indicator extends PanelMenu.Button {
    _init(extension) {
        super._init(0.0, 'RooTerm', false);
        this.extension = extension;

        this.add_child(new St.Icon({
            icon_name: 'utilities-terminal-symbolic',
            style_class: 'system-status-icon rooterm-icon',
        }));

        var self = this;
        var prefsItem = new PopupMenu.PopupMenuItem('Preferences');
        prefsItem.connect('activate', function() {
            Gio.DBus.session.call(
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'preferences',
                null, null, Gio.DBusCallFlags.NONE, 2000, null,
                self.extension.onDBusFinished.bind(self.extension, 'preferences')
            );
        });
        this.menu.addMenuItem(prefsItem);

        var aboutItem = new PopupMenu.PopupMenuItem('About');
        aboutItem.connect('activate', function() {
            Gio.DBus.session.call(
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'about',
                null, null, Gio.DBusCallFlags.NONE, 2000, null,
                self.extension.onDBusFinished.bind(self.extension, 'about')
            );
        });
        this.menu.addMenuItem(aboutItem);

        var quitItem = new PopupMenu.PopupMenuItem('Quit');
        quitItem.connect('activate', function() {
            Gio.DBus.session.call(
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'quit',
                new GLib.Variant('(b)', [false]),
                null, Gio.DBusCallFlags.NONE, 2000, null,
                self.extension.onDBusFinished.bind(self.extension, 'quit')
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
                DBUS_DEST, DBUS_PATH, DBUS_IFACE, 'toggle',
                null, null, Gio.DBusCallFlags.NONE, 2000, null,
                this.extension.onDBusFinished.bind(this.extension, 'toggle')
            );
            return Clutter.EVENT_PROPAGATE;
        }
        if (event.get_button() === Clutter.BUTTON_SECONDARY) {
            this.menu.toggle();
        }
        return Clutter.EVENT_PROPAGATE;
    }
});
