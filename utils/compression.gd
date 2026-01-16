const ByteUtils = Quack.ByteUtils

enum {
	TIMES_COMPRESSED, # 0
	BEGIN_UNCOMPRESSED, # 1
	SIZE_INDICATOR_BEGIN = 1 # 1
}
const SIZE_INDICATOR_BYTES = 2
const SIZE_INDICATOR_BYTES_BIG = 4

static func is_compressed(bytes: PackedByteArray) -> bool:
	return bytes[TIMES_COMPRESSED]

static func get_num_times_compressed(bytes: PackedByteArray) -> int:
	return bytes[TIMES_COMPRESSED]

static func get_begin_offset(bytes: PackedByteArray, big: bool = false) -> int:
	var _amnt := bytes[TIMES_COMPRESSED]
	var _ret := TIMES_COMPRESSED + bytes[TIMES_COMPRESSED] * (4 if big else 2) + 1
	return TIMES_COMPRESSED + bytes[TIMES_COMPRESSED] * (4 if big else 2) + 1

static func get_contents_decompressed_size(times_compressed: int, bytes: PackedByteArray, big: bool = false) -> int:
	return bytes.decode_u16(SIZE_INDICATOR_BEGIN + (times_compressed - 1) * SIZE_INDICATOR_BYTES) if not big else bytes.decode_u32(SIZE_INDICATOR_BEGIN+(times_compressed-1)*SIZE_INDICATOR_BYTES)

static func get_contents(bytes: PackedByteArray, big: bool = false) -> PackedByteArray:
	return bytes.slice(get_begin_offset(bytes, big))

static func get_bytes_decompressed(times_compressed: int, bytes: PackedByteArray, contents: PackedByteArray, compression_mode: FileAccess.CompressionMode = FileAccess.COMPRESSION_FASTLZ, big: bool = false) -> PackedByteArray:
	var _size := get_contents_decompressed_size(times_compressed,bytes,big)
	return contents.decompress(get_contents_decompressed_size(times_compressed,bytes,big),compression_mode)

static func repeated_compress(bytes: PackedByteArray, compression_mode: FileAccess.CompressionMode = FileAccess.COMPRESSION_FASTLZ, big: bool = false) -> PackedByteArray:
	var final: PackedByteArray = [0]
	var num_times_compressed: int = 0
	var compressed: PackedByteArray
	
	while true:
		compressed = bytes.compress(compression_mode)
		if compressed.size() < bytes.size():
			num_times_compressed += 1
			add_compression(final,final.size(),bytes.size(),big)
			bytes = compressed
		else:
			break
	
	final[0] = num_times_compressed
	final.append_array(bytes)
	return final

static func add_compression(final: PackedByteArray, offset: int, compressed_size: int, big: bool = false) -> void:
	if big:
		final.resize(offset+SIZE_INDICATOR_BYTES_BIG)
		final.encode_u32(offset,compressed_size)
	else:
		final.resize(offset+SIZE_INDICATOR_BYTES)
		final.encode_u16(offset,compressed_size)

static func repeated_decompress(bytes: PackedByteArray, compression_mode: FileAccess.CompressionMode = FileAccess.COMPRESSION_FASTLZ, big: bool = false) -> PackedByteArray:
	if !is_compressed(bytes):
		return bytes.slice(BEGIN_UNCOMPRESSED)
	var num_times_compressed: int = get_num_times_compressed(bytes)
	assert(num_times_compressed, "trying to decompress packet that's not been compressed, byte at idx %s is %s."%[TIMES_COMPRESSED,num_times_compressed])
	var contents: PackedByteArray = get_contents(bytes,big)
	for i in num_times_compressed:
		contents = get_bytes_decompressed(num_times_compressed - i,bytes,contents,compression_mode,big)
	return contents
