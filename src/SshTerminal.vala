/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace RooTerm
{
	/**
	 * VTE terminal for one SSH session on a {@link Connection}.
	 */
	public class SshTerminal : Gtk.Box
	{
		public Connection connection;
		public Vte.Terminal terminal;
		public SshStream stream;
		public string cwd = "";
		private string window_title = "";
		/**
		 * Mark for the host-tree session icon (active look is focus, not this).
		 */
		public SessionState state = SessionState.IDLE;
		private bool selected = true;
		private uint settle_timeout = 0;
		private Gtk.Box close_bar;
		private Gtk.Label close_label;
		private Gtk.ProgressBar close_progress;
		private uint close_tick = 0;
		private int close_left = 0;
		private bool close_paused = false;
		private bool close_armed = false;

		/**
		 * Emitted when the SSH child process exits.
		 */
		public signal void exited();

		/**
		 * Emitted when the close countdown finishes (tab should be closed).
		 */
		public signal void close_tab();

		/**
		 * Emitted when {@link cwd} (and thus {@link label}) changes.
		 */
		public signal void label_changed();

		/**
		 * Emitted when {@link state} changes (busy / ready / idle / dead).
		 */
		public signal void state_changed();

		/**
		 * Build a scrolled VTE for ``connection`` (call {@link spawn} to start SSH).
		 *
		 * @param connection Host to open
		 * @param font Pango font string (Ásbrú ``terminal font``)
		 * @param in_stream Optional flags bag (``install_key`` / ``list_containers``); wired stream is always new
		 */
		public SshTerminal(Connection connection, string font = "Monospace 9", SshStream? in_stream = null)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
			this.connection = connection;
			this.terminal = new Vte.Terminal() {
				hexpand = true,
				vexpand = true,
				font_desc = Pango.FontDescription.from_string(font)
			};
			this.terminal.set_size(80, 24);
			this.append(new Gtk.ScrolledWindow() {
				child = this.terminal,
				hexpand = true,
				vexpand = true
			});
			this.close_progress = new Gtk.ProgressBar() {
				fraction = 1.0,
				hexpand = true
			};
			this.close_label = new Gtk.Label("Closing in 30 seconds…") {
				hexpand = true,
				xalign = 0.0f
			};
			var keep = new Gtk.Button.with_label("Keep open");
			keep.clicked.connect(() => {
				this.close_paused = true;
				if (this.close_tick != 0) {
					GLib.Source.remove(this.close_tick);
					this.close_tick = 0;
				}
				this.close_label.label = "Kept open - Enter to reconnect";
				this.close_progress.fraction = 1.0;
			});
			var close_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			close_row.append(this.close_label);
			close_row.append(keep);
			this.close_bar = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				visible = false,
				margin_start = 8,
				margin_end = 8,
				margin_top = 4,
				margin_bottom = 6
			};
			this.close_bar.append(this.close_progress);
			this.close_bar.append(close_row);
			this.append(this.close_bar);

			this.stream = new SshStream(this.terminal, this.connection);
			if (in_stream != null) {
				this.stream.install_key = in_stream.install_key;
				this.stream.list_containers = in_stream.list_containers;
			}
			this.stream.label_changed.connect(() => {
				this.label_changed();
			});

			var shortcuts = new Gtk.ShortcutController() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
				scope = Gtk.ShortcutScope.LOCAL
			};
			shortcuts.add_shortcut(new Gtk.Shortcut(
				Gtk.ShortcutTrigger.parse_string("<Control><Shift>c"),
				new Gtk.CallbackAction(() => {
					this.terminal.copy_clipboard_format(Vte.Format.TEXT);
					return true;
				})
			));
			shortcuts.add_shortcut(new Gtk.Shortcut(
				Gtk.ShortcutTrigger.parse_string("<Control><Shift>v"),
				new Gtk.CallbackAction(() => {
					this.terminal.paste_clipboard();
					return true;
				})
			));
			this.terminal.add_controller(shortcuts);
			var keys = new Gtk.EventControllerKey() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			keys.key_pressed.connect((keyval, keycode, mods) => {
				if (this.state != SessionState.DEAD) {
					return false;
				}
				if (keyval != Gdk.Key.Return && keyval != Gdk.Key.KP_Enter) {
					return false;
				}
				this.reconnect();
				return true;
			});
			this.terminal.add_controller(keys);

			this.terminal.child_exited.connect((status) => {
				var exit_code = (status >> 8) & 0xff;
				GLib.debug("ssh child exited status=%d exit=%d name=%s", status, exit_code, this.connection.name);
				if (this.stream.session_log != null) {
					this.stream.session_log.printf("\n# exited %d\n", exit_code);
					this.stream.session_log.flush();
					this.stream.session_log = null;
				}
				if (this.settle_timeout != 0) {
					GLib.Source.remove(this.settle_timeout);
					this.settle_timeout = 0;
				}
				if (this.stream.install_identity.length > 0) {
					this.close_tab();
					this.exited();
					return;
				}
				if (this.state != SessionState.DEAD) {
					this.state = SessionState.DEAD;
					this.state_changed();
				}
				if (this.selected) {
					var done = "\r\n[ssh exited: " + exit_code.to_string()
						+ " - Enter to reconnect, or wait to close]\r\n";
					this.terminal.feed(done.data);
					this.start_close();
				} else {
					var done = "\r\n[ssh exited: " + exit_code.to_string()
						+ " - open this tab to close, or Enter to reconnect]\r\n";
					this.terminal.feed(done.data);
				}
				this.exited();
			});
			this.terminal.termprop_changed.connect((prop) => {
				if (prop == Vte.TERMPROP_XTERM_TITLE) {
					size_t size;
					var title = this.terminal.dup_termprop_string(prop, out size);
					this.window_title = title != null ? title : "";
					this.label_changed();
					return;
				}
				if (prop != Vte.TERMPROP_CURRENT_DIRECTORY_URI) {
					return;
				}
				var uri = this.terminal.ref_termprop_uri(prop);
				if (uri == null) {
					return;
				}
				var path = GLib.File.new_for_uri(uri.to_string()).get_path();
				if (path == null) {
					return;
				}
				this.cwd = path;
				this.label_changed();
			});
			this.terminal.window_title_changed.connect(() => {
				var title = this.terminal.get_window_title();
				this.window_title = title != null ? title : "";
				this.label_changed();
			});
			this.terminal.contents_changed.connect(() => {
				if (this.selected || this.state == SessionState.DEAD) {
					return;
				}
				if (this.settle_timeout != 0) {
					GLib.Source.remove(this.settle_timeout);
					this.settle_timeout = 0;
				}
				if (this.state != SessionState.BUSY) {
					this.state = SessionState.BUSY;
					this.state_changed();
				}
				this.settle_timeout = GLib.Timeout.add(1500, () => {
					this.settle_timeout = 0;
					if (this.selected || this.state != SessionState.BUSY) {
						return false;
					}
					this.state = SessionState.READY;
					this.state_changed();
					return false;
				});
			});
		}

		/**
		 * Mark this tab selected on the visible host page (clears busy/ready).
		 * Focusing a dead tab starts the close countdown.
		 *
		 * @param on true when this tab is the focused one
		 */
		public void select(bool on)
		{
			if (this.selected == on) {
				return;
			}
			this.selected = on;
			if (this.state == SessionState.DEAD) {
				if (on && !this.close_paused && !this.close_armed) {
					this.start_close();
				}
				return;
			}
			if (this.settle_timeout != 0) {
				GLib.Source.remove(this.settle_timeout);
				this.settle_timeout = 0;
			}
			if (this.state == SessionState.IDLE) {
				return;
			}
			this.state = SessionState.IDLE;
			this.state_changed();
		}

		/**
		 * Show the draining close bar and start a 30s countdown.
		 */
		private void start_close()
		{
			if (this.close_armed || this.close_paused) {
				return;
			}
			this.close_armed = true;
			this.close_left = 30;
			this.close_bar.visible = true;
			this.close_label.label = "Closing in 30 seconds…";
			this.close_progress.fraction = 1.0;
			this.terminal.grab_focus();
			if (this.close_tick != 0) {
				GLib.Source.remove(this.close_tick);
			}
			this.close_tick = GLib.Timeout.add_seconds(1, () => {
				if (this.close_paused) {
					this.close_tick = 0;
					return false;
				}
				this.close_left--;
				if (this.close_left <= 0) {
					this.close_tick = 0;
					this.close_bar.visible = false;
					this.close_tab();
					return false;
				}
				this.close_label.label = "Closing in " + this.close_left.to_string() + " seconds…";
				this.close_progress.fraction = (double) this.close_left / 30.0;
				return true;
			});
		}

		/**
		 * Re-spawn SSH in this tab after a dead exit (Enter).
		 */
		public void reconnect()
		{
			if (this.state != SessionState.DEAD) {
				return;
			}
			this.close_paused = false;
			this.close_armed = false;
			if (this.close_tick != 0) {
				GLib.Source.remove(this.close_tick);
				this.close_tick = 0;
			}
			this.close_bar.visible = false;
			this.stream.sent_secret = false;
			this.stream.hide_input = false;
			this.stream.log_line = -1;
			this.stream.sudo_sent = false;
			this.stream.sudo_done = false;
			this.stream.list_sent = false;
			this.stream.list_parsed = false;
			this.stream.lxc_sent = false;
			this.stream.prompt_hint = "";
			this.state = SessionState.IDLE;
			this.state_changed();
			this.spawn();
		}

		/**
		 * Tab / title label: host name, plus prompt, OSC title, or cwd when known.
		 *
		 * @return Display string
		 */
		public string label()
		{
			var detail = this.detail();
			if (detail.length == 0) {
				return this.connection.name;
			}
			return this.connection.name + "  " + detail;
		}

		/**
		 * Dynamic part of {@link label} (prompt preferred; OSC is often absent over SSH).
		 *
		 * @return Detail string or empty
		 */
		private string detail()
		{
			if (this.stream.prompt_hint.length > 0) {
				return this.stream.prompt_hint;
			}
			if (this.window_title.length > 0) {
				return this.window_title;
			}
			return this.cwd;
		}

		/**
		 * Spawn ``ssh`` for this connection; password / passphrase fed on prompt.
		 * When {@link SshStream.install_key} is set, runs ``ssh-copy-id`` instead.
		 */
		public void spawn()
		{
			this.stream.sudo_sent = false;
			this.stream.sudo_done = false;
			this.stream.list_sent = false;
			this.stream.list_parsed = false;
			this.stream.lxc_sent = false;
			this.stream.sent_secret = false;
			if (this.connection.pass.length == 0
					&& this.connection.auth != "manual"
					&& (this.connection.auth == "password"
						|| this.connection.sudo_after_login
						|| this.stream.install_key)) {
				var secret_uuid = this.connection.uuid;
				if (this.connection.lxc_container && this.connection.parent_uuid.length > 0) {
					secret_uuid = this.connection.parent_uuid;
				}
				try {
					var pass = Secret.password_lookup_sync(
						new Secret.Schema(
							"org.roojs.rooterm.Connection", Secret.SchemaFlags.NONE,
							"uuid", Secret.SchemaAttributeType.STRING
						),
						null,
						"uuid", secret_uuid
					);
					this.connection.pass = pass != null ? pass : "";
					GLib.debug("spawn secret uuid=%s pass_len=%d name=%s",
						secret_uuid, this.connection.pass.length, this.connection.name);
				} catch (GLib.Error e) {
					GLib.warning("secret load failed uuid=%s: %s", secret_uuid, e.message);
				}
			}
			var target = this.connection.user + "@" + this.connection.host
				+ ":" + this.connection.port.to_string();
			string[] argv;
			if (this.stream.install_key) {
				var home = GLib.Environment.get_home_dir();
				var ed = GLib.Path.build_filename(home, ".ssh", "id_ed25519.pub");
				var rsa = GLib.Path.build_filename(home, ".ssh", "id_rsa.pub");
				var pub = "";
				if (GLib.FileUtils.test(ed, GLib.FileTest.IS_REGULAR)) {
					pub = ed;
				}
				if (pub.length == 0 && GLib.FileUtils.test(rsa, GLib.FileTest.IS_REGULAR)) {
					pub = rsa;
				}
				if (pub.length == 0) {
					this.terminal.feed("No ~/.ssh/id_ed25519.pub or id_rsa.pub found.\r\n".data);
					return;
				}
				var identity = pub;
				if (pub.has_suffix(".pub")) {
					identity = pub.substring(0, pub.length - 4);
				}
				this.stream.install_identity = identity;
				argv = {
					"ssh-copy-id",
					"-p", this.connection.port.to_string(),
					"-i", pub,
					this.connection.user + "@" + this.connection.host
				};
				this.terminal.feed(("Installing key via ssh-copy-id → " + target + " …\r\n").data);
			} else {
				argv = {
					"ssh",
					"-p", this.connection.port.to_string()
				};
				foreach (var fwd in this.connection.forwards) {
					argv += "-L";
					argv += fwd.local_host + ":" + fwd.local_port.to_string()
						+ ":" + fwd.remote_host + ":" + fwd.remote_port.to_string();
				}
				if ((this.connection.auth == "publickey" || this.connection.auth == "ssh_key")
						&& this.connection.public_key.length > 0) {
					argv += "-i";
					argv += this.connection.public_key;
				}
				foreach (var opt in this.connection.options.strip().split_set(" \t")) {
					if (opt.length == 0) {
						continue;
					}
					argv += opt;
				}
				argv += this.connection.user + "@" + this.connection.host;
				this.terminal.feed(("Connecting to " + target + " …\r\n").data);
			}

			var log_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "asbru", "session_logs"
			);
			GLib.DirUtils.create_with_parents(log_dir, 0755);
			var stamp = new GLib.DateTime.now_local().format("%Y%m%d_%H%M%S");
			var log_path = GLib.Path.build_filename(
				log_dir, this.connection.uuid + "_" + this.connection.name + "_" + stamp + ".txt"
			);
			this.stream.session_log = GLib.FileStream.open(log_path, "w");
			if (this.stream.session_log != null) {
				this.stream.session_log.printf(
					"# RooTerm %s %s started %s\n", this.connection.name, target, stamp
				);
				this.stream.session_log.flush();
				GLib.debug("session log path=%s", log_path);
			} else {
				GLib.warning("session log open failed path=%s", log_path);
			}

			GLib.debug("ssh spawn name=%s target=%s install_key=%s",
				this.connection.name, target, this.stream.install_key.to_string());
			this.terminal.spawn_async(
				Vte.PtyFlags.DEFAULT,
				null,
				argv,
				null,
				GLib.SpawnFlags.SEARCH_PATH,
				null,
				-1,
				null,
				(term, pid, error) => {
					if (error != null) {
						GLib.warning("ssh spawn failed: %s", error.message);
						var fail = "spawn failed: " + error.message + "\r\n";
						this.terminal.feed(fail.data);
						return;
					}
					GLib.debug("ssh pid=%d name=%s", pid, this.connection.name);
				}
			);
		}
	}
}
