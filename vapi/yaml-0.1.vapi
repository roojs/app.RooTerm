/* Minimal libyaml event-parser bindings for Ásbrú config load. */
[CCode (cheader_filename = "yaml.h")]
namespace Yaml {
	[CCode (cname = "yaml_event_type_t", has_type_id = false)]
	public enum EventType {
		[CCode (cname = "YAML_NO_EVENT")]
		NO,
		[CCode (cname = "YAML_STREAM_START_EVENT")]
		STREAM_START,
		[CCode (cname = "YAML_STREAM_END_EVENT")]
		STREAM_END,
		[CCode (cname = "YAML_DOCUMENT_START_EVENT")]
		DOCUMENT_START,
		[CCode (cname = "YAML_DOCUMENT_END_EVENT")]
		DOCUMENT_END,
		[CCode (cname = "YAML_ALIAS_EVENT")]
		ALIAS,
		[CCode (cname = "YAML_SCALAR_EVENT")]
		SCALAR,
		[CCode (cname = "YAML_SEQUENCE_START_EVENT")]
		SEQUENCE_START,
		[CCode (cname = "YAML_SEQUENCE_END_EVENT")]
		SEQUENCE_END,
		[CCode (cname = "YAML_MAPPING_START_EVENT")]
		MAPPING_START,
		[CCode (cname = "YAML_MAPPING_END_EVENT")]
		MAPPING_END
	}

	[CCode (cname = "yaml_event_t", destroy_function = "yaml_event_delete", has_type_id = false)]
	public struct Event {
		public EventType type;
		[CCode (cname = "data.scalar.value")]
		public string? data_scalar_value;
	}

	[CCode (cname = "yaml_parser_t", destroy_function = "yaml_parser_delete", has_type_id = false)]
	public struct Parser {
		[CCode (cname = "yaml_parser_initialize")]
		public Parser();

		public void set_input_string([CCode (array_length_type = "size_t")] uint8[] input);

		public int parse(out Event event);
	}
}
