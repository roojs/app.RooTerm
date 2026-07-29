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
	public class SshTerminal : Terminal
	{
		public SshStream stream;
		private string window_title = "";
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
		 * Build a scrolled VTE for ``connection`` (call {@link spawn} to start SSH).
		 *
		 * @param connection Host to open
		 * @param font Pango font string (Ásbrú ``terminal font``)
		 * @param in_stream Optional stream to adopt (flags bag or pre-wired); otherwise a new stream
		 */
		public SshTerminal(Connection connection, string font = "Monospace 9", SshStream? in_stream = null)
		{
			base(connection, font);
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

			if (in_stream != null) {
				this.stream = in_stream;
				this.stream.attach(this.terminal, this.connection);
			} else {
				this.stream = new SshStream(this.terminal, this.connection);
			}
			this.stream.label_changed.connect(() => {
				this.label_changed();
			});

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
				if (prop != Vte.TERMPROP_XTERM_TITLE) {
					return;
				}
				size_t size;
				var title = this.terminal.dup_termprop_string(prop, out size);
				this.window_title = title != null ? title : "";
				this.label_changed();
			});
			this.terminal.window_title_changed.connect(() => {
				var title = this.terminal.get_window_title();
				this.window_title = title != null ? title : "";
				this.label_changed();
			});
		}

		/**
		 * Mark this tab selected; focusing a dead tab starts the close countdown.
		 *
		 * @param on true when this tab is the focused one
		 */
		public override void select(bool on)
		{
			if (this.state == SessionState.DEAD) {
				if (this.selected == on) {
					return;
				}
				this.selected = on;
				if (on && !this.close_paused && !this.close_armed) {
					this.start_close();
				}
				return;
			}
			base.select(on);
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
			this.stream.hide_input = false;
			this.stream.log_line = -1;
			this.stream.prompt_hint = "";
			this.state = SessionState.IDLE;
			this.spawn();
		}

		/**
		 * {@inheritDoc}
		 */
		public override string label()
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
		public override void spawn()
		{
			if (this.connection.pass.length == 0
					&& this.connection.auth != "manual"
					&& (this.connection.auth == "password"
						|| this.connection.sudo_after_login
						|| this.stream.install_key)) {
				var secret_uuid = this.connection.uuid;
				if (this.connection.kind == ConnectionKind.LXC && this.connection.parent_uuid.length > 0) {
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
			if (this.connection.passphrase.length == 0
					&& (this.connection.auth == "ssh_key"
						|| this.connection.auth == "publickey"
						|| this.stream.install_key)) {
				var identity = this.connection.public_key;
				if (identity.length == 0) {
					identity = GLib.Path.build_filename(
						GLib.Environment.get_home_dir(), ".ssh", "id_ed25519"
					);
				}
				try {
					var phrase = Secret.password_lookup_sync(
						new Secret.Schema(
							"org.roojs.rooterm.SshKey", Secret.SchemaFlags.NONE,
							"path", Secret.SchemaAttributeType.STRING
						),
						null,
						"path", identity
					);
					this.connection.passphrase = phrase != null ? phrase : "";
					GLib.debug("spawn key secret path=%s phrase_len=%d name=%s",
						identity, this.connection.passphrase.length, this.connection.name);
				} catch (GLib.Error e) {
					GLib.warning("key secret load failed path=%s: %s", identity, e.message);
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
				if (this.stream.install_identity.length > 0) {
					pub = this.stream.install_identity;
					if (!pub.has_suffix(".pub")) {
						pub = pub + ".pub";
					}
				}
				if (pub.length == 0 && this.connection.public_key.length > 0) {
					pub = this.connection.public_key;
					if (!pub.has_suffix(".pub")) {
						pub = pub + ".pub";
					}
				}
				if (pub.length == 0 && GLib.FileUtils.test(ed, GLib.FileTest.IS_REGULAR)) {
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
