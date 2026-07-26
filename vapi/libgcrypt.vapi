/* Minimal object-style libgcrypt bindings for Ásbrú Blowfish decrypt. */
[CCode (cheader_filename = "gcrypt.h")]
namespace GCrypt {
	[CCode (cname = "gcry_error_t")]
	public struct Error : uint {
	}

	[CCode (cname = "enum gcry_ctl_cmds")]
	public enum ControlCmd {
		[CCode (cname = "GCRYCTL_DISABLE_SECMEM")]
		DISABLE_SECMEM = 37,
		[CCode (cname = "GCRYCTL_INITIALIZATION_FINISHED")]
		INITIALIZATION_FINISHED = 38
	}

	[CCode (cname = "enum gcry_md_algos")]
	public enum MdAlgo {
		[CCode (cname = "GCRY_MD_MD5")]
		MD5 = 1
	}

	[CCode (cname = "enum gcry_cipher_algos")]
	public enum CipherAlgo {
		[CCode (cname = "GCRY_CIPHER_BLOWFISH")]
		BLOWFISH = 4
	}

	[CCode (cname = "enum gcry_cipher_modes")]
	public enum CipherMode {
		[CCode (cname = "GCRY_CIPHER_MODE_CBC")]
		CBC = 3
	}

	/**
	 * Library-wide init / control (not instance state).
	 */
	[CCode (cname = "GCrypt")]
	namespace Library {
		[CCode (cname = "gcry_check_version")]
		public static unowned string? check_version (string? req_version);

		[CCode (cname = "gcry_control")]
		public static Error control (ControlCmd cmd, ...);
	}

	/**
	 * Message digest handle (``gcry_md_hd_t``).
	 */
	[Compact]
	[CCode (cname = "struct gcry_md_handle", free_function = "gcry_md_close", has_type_id = false)]
	public class Md {
		[CCode (cname = "gcry_md_open")]
		public static Error open (out Md md, MdAlgo algo, uint flags = 0);

		[CCode (cname = "gcry_md_write")]
		public void write ([CCode (array_length_type = "size_t")] uint8[] data);

		[CCode (cname = "gcry_md_write")]
		public void write_full (void* data, size_t length);

		[CCode (cname = "gcry_md_read")]
		public unowned uint8* read_bytes (MdAlgo algo);

		[CCode (cname = "gcry_md_get_algo_dlen")]
		public static uint digest_length (MdAlgo algo);
	}

	/**
	 * Cipher handle (``gcry_cipher_hd_t``).
	 */
	[Compact]
	[CCode (cname = "struct gcry_cipher_handle", free_function = "gcry_cipher_close", has_type_id = false)]
	public class Cipher {
		[CCode (cname = "gcry_cipher_open")]
		public static Error open (out Cipher cipher, CipherAlgo algo, CipherMode mode, uint flags = 0);

		[CCode (cname = "gcry_cipher_setkey")]
		public Error set_key ([CCode (array_length_type = "size_t")] uint8[] key);

		[CCode (cname = "gcry_cipher_setiv")]
		public Error set_iv ([CCode (array_length_type = "size_t")] uint8[] iv);

		[CCode (cname = "gcry_cipher_decrypt")]
		public Error decrypt_full (void* output, size_t output_size, void* input, size_t input_size);

		[CCode (cname = "gcry_cipher_get_algo_blklen")]
		public static size_t block_length (CipherAlgo algo);
	}
}
