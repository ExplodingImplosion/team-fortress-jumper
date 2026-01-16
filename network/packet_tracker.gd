const Compression = preload("res://utils/compression.gd")
var history: Array[PackedByteArray]
var history_offset: int = -1

var packet_map: Dictionary
var packet_signature_map: Dictionary

var packets: Array[PackedByteArray]

func add_packet(_from: int, packet: PackedByteArray) -> void:
	packets.append(packet)

func save(to: String) -> void:
	var file := FileAccess.open(to,FileAccess.WRITE)
	var file_err := FileAccess.get_open_error()
	if file_err != OK:
		return Console.push_err("File %s couldn't be written. Error %s."%[to,error_string(file_err)])
	var status := file.store_buffer(Compression.repeated_compress(var_to_bytes(packets),FileAccess.COMPRESSION_ZSTD))
	Console.write("Storing %s %s."%[to,"succeeded" if status else "failed"])
	file.flush()

static func get_packets(from: String) -> Array[PackedByteArray]:
	if FileAccess.file_exists(from):
		return bytes_to_var(Compression.repeated_decompress(FileAccess.get_file_as_bytes(from),FileAccess.COMPRESSION_ZSTD))
	else:
		return []

func _init(tracker_size: int) -> void:
	history.resize(tracker_size)

func maps_erase_by_packet(packet: PackedByteArray) -> void:
	packet_map.erase(packet_signature_map[packet])
	packet_signature_map.erase(packet)

func maps_erase_by_signature(signature: int) -> void:
	packet_signature_map.erase(packet_map[signature])
	packet_map.erase(signature)

func maps_add_packet(packet: PackedByteArray, signature: int) -> void:
	packet_map[signature] = packet
	packet_signature_map[packet] = signature

func add_to_history_by_signature(packet: PackedByteArray, _signature: int) -> void:
	increment_history_offset()
	var replaced_packet: PackedByteArray = history[history_offset]
	if !replaced_packet.is_empty() and packet_signature_map.has(replaced_packet):
		maps_erase_by_packet(replaced_packet)
	history[history_offset] = packet

func add_to_history(packet: PackedByteArray) -> void:
	increment_history_offset()
	history[history_offset] = packet

func get_history_offset_incremented() -> int:
	return wrapi(history_offset + 1, 0, history.size())

func increment_history_offset() -> void:
	history_offset = get_history_offset_incremented()

func get_previous_packet(frames_behind: int) -> PackedByteArray:
	assert(frames_behind >= 0, "frames_behind must be a positive number, but is %s."%[frames_behind])
	# maybe change this to some kind of wrapi
	return history[history_offset - frames_behind]

func get_most_recent_packet() -> PackedByteArray:
	return history[history_offset]

func size() -> int:
	return history.size()
