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
	 * Ásbrú CM Blowfish/CBC password decrypt (Crypt::CBC opensslv1) via libgcrypt.
	 */
	public class AsbruCipher
	{
		private static bool gcrypt_ready = false;

		/**
		 * Decrypt a hex-encoded Ásbrú ``pass`` / ``passphrase`` field.
		 *
		 * @param hex Hex ciphertext (often beginning with Salted__)
		 * @return Plaintext, or empty string if ``hex`` is empty / decrypt fails
		 */
		public static string decrypt_hex(string hex)
		{
			if (hex.length == 0) {
				return "";
			}
			if (!AsbruCipher.gcrypt_ready) {
				if (GCrypt.Library.check_version(null) == null) {
					GLib.warning("asbru decrypt: gcrypt init failed");
					return "";
				}
				GCrypt.Library.control(GCrypt.ControlCmd.DISABLE_SECMEM, 0);
				GCrypt.Library.control(GCrypt.ControlCmd.INITIALIZATION_FINISHED, 0);
				AsbruCipher.gcrypt_ready = true;
			}

			if ((hex.length % 2) != 0) {
				GLib.warning("asbru decrypt failed for blob length=%d", hex.length);
				return "";
			}
			if (!GLib.Regex.match_simple("^[0-9a-fA-F]+$", hex)) {
				GLib.warning("asbru decrypt failed for blob length=%d", hex.length);
				return "";
			}

			var bin = new uint8[hex.length / 2];
			var i = 0;
			while (i < bin.length) {
				bin[i] = (uint8) uint64.parse("0x" + hex.substring(i * 2, 2));
				i++;
			}
			if (bin.length < 16) {
				GLib.warning("asbru decrypt failed for blob length=%d", hex.length);
				return "";
			}
			if (GLib.Memory.cmp(bin, "Salted__".data, 8) != 0) {
				GLib.warning("asbru decrypt: missing Salted__ header");
				return "";
			}

			var salt = bin[8:16];
			var ct = bin[16:bin.length];
			var block = GCrypt.Cipher.block_length(GCrypt.CipherAlgo.BLOWFISH);
			if (ct.length == 0 || block == 0 || (ct.length % block) != 0) {
				GLib.warning("asbru decrypt: bad ciphertext length");
				return "";
			}

			var pass = "PAC Manager (David Torrejon Vaquerizas, david.tv@gmail.com)";
			var key_iv = new uint8[64];
			var prev = new uint8[16];
			var have = 0;
			var first = true;
			while (have < 64) {
				GCrypt.Md md;
				if (GCrypt.Md.open(out md, GCrypt.MdAlgo.MD5) != 0) {
					GLib.warning("asbru decrypt: md open failed");
					return "";
				}
				if (!first) {
					md.write(prev);
				}
				md.write_full(pass, pass.length);
				md.write(salt);
				GLib.Memory.copy(prev, md.read_bytes(GCrypt.MdAlgo.MD5), 16);
				var copy = 16;
				if (have + copy > 64) {
					copy = 64 - have;
				}
				GLib.Memory.copy(key_iv[have:have + copy], prev, copy);
				have += copy;
				first = false;
			}

			GCrypt.Cipher cipher;
			if (GCrypt.Cipher.open(out cipher, GCrypt.CipherAlgo.BLOWFISH, GCrypt.CipherMode.CBC) != 0) {
				GLib.warning("asbru decrypt: cipher open failed");
				return "";
			}
			if (cipher.set_key(key_iv[0:56]) != 0 || cipher.set_iv(key_iv[56:64]) != 0) {
				GLib.warning("asbru decrypt: setkey/setiv failed");
				return "";
			}

			var plain = new uint8[ct.length];
			if (cipher.decrypt_full(plain, plain.length, ct, ct.length) != 0) {
				GLib.warning("asbru decrypt: decrypt failed");
				return "";
			}

			var pad = plain[plain.length - 1];
			if (pad < 1 || pad > block) {
				GLib.warning("asbru decrypt: bad pkcs padding");
				return "";
			}
			var out_len = plain.length - pad;
			var result = new uint8[out_len + 1];
			GLib.Memory.copy(result, plain, out_len);
			result[out_len] = 0;
			return (string) result;
		}
	}
}
