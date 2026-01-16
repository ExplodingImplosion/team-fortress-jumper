extends StreamPeerBuffer
const ByteUtils = preload("res://utils/byte_utils.gd")
const StreamPeerBitBuffer = preload("res://utils/stream_peer_bit_buffer.gd")

#var position_bits: int = 0

var bool_position: int = 0
var num_allocated_bools: int = 0
var bool_bytes: int = 0

func _to_string() -> String:
	return "StreamPeerBitBuffer (%s, %s allocated bools, %s bools used, %s bytes used)"%[
		String.humanize_size(get_size()),num_allocated_bools,bool_position,get_var_pos()
	]

func reset() -> void:
	bool_position = 0
	seek(bool_bytes)

func _init(with_size: int = 0, allocated_bools: int = 1024) -> void:
	@warning_ignore("integer_division")
	bool_bytes = (allocated_bools+7)/8 # Same as: ByteUtils.which_byte_is_bit_in(allocated_bools)
	num_allocated_bools = bool_bytes * 8
	resize(with_size)
	seek(bool_bytes)

func export(until_position: bool = true) -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray([0,0,0,0])
	data.encode_u32(0,bool_position)
	data.append_array(get_bools(until_position))
	data.append_array(get_non_bools(until_position))
	return data

func import(bytes: PackedByteArray, ) -> void:
	var max_bool_idx: int = bytes.decode_u32(0)
	data_array = bytes.slice(4)
	bool_bytes = (max_bool_idx+7)/8
	num_allocated_bools = bool_bytes * 8
	reset()

func get_bools(until_position: bool = true) -> PackedByteArray:
	return data_array.slice(0, (bool_position+7)/8 if until_position else bool_bytes)

static func decode(bytes: PackedByteArray) -> StreamPeerBitBuffer:
	# set to 1 so that buffer doesn't seek to nonexistent idx
	var buffer := StreamPeerBitBuffer.new(1,0)
	buffer.import(bytes)
	return buffer

func get_non_bools(until_position: bool = true) -> PackedByteArray:
	return data_array.slice(bool_bytes,get_position()+1 if until_position else 0x7FFFFFFF)

func get_bools_as_array() -> Array[bool]:
	var array: Array[bool] = []
	array.resize(num_allocated_bools)
	
	var pos := bool_position
	bool_position = 0
	
	for i in num_allocated_bools:
		array[i] = get_bool()
	
	bool_position = pos
	
	return array

func ensure_bools_allocated() -> void:
	assert(bool_position <= num_allocated_bools, "Yo bool pos %s shouldn't be bigger than num allocated bools %s"%[bool_position,num_allocated_bools])
	if bool_position == num_allocated_bools:
		reallocate_bools()

func reallocate_bools(amount: int = 1) -> void:
	assert(amount >= 1, "Amount can't be less than 1 but is %s."%amount)
	
	@warning_ignore("integer_division")
	var num_new_bytes: int = (amount+7)/8
	bool_bytes += num_new_bytes
	num_allocated_bools = bool_bytes * 8
	
	var non_bools := get_non_bools(false)
	var pos := get_position()
	
	# Make room for new bools
	resize(get_size()+num_new_bytes)
	seek(bool_bytes)
	
	# Move all other data ahead by num_new_bytes
	var err := put_data(non_bools)
	assert(err == OK, "Yo this should never be an error, but got error %s."%error_string(err))
	
	# Go back to original position (+ new bytes), like nothing ever happened
	seek(pos+num_new_bytes)

func put_bool(value: bool) -> void:
	ensure_bools_allocated()
	@warning_ignore("integer_division")
	var idx: int = bool_position/8
	var bit: int = 1 << bool_position%8
	var pos := get_position()
	seek(idx)
	if value:
		put_u8(data_array[idx] | bit)
	else:
		put_u8(data_array[idx] & ~bit)
	seek(pos)
	bool_position += 1

func put_eval(evaluation: bool) -> bool:
	put_bool(evaluation)
	return evaluation

func get_bool() -> bool:
	Console.get_assertfail_msg(bool_position < num_allocated_bools,"Tried to access unallocated bool at position %s with %s allocated bools."%[bool_position,num_allocated_bools])
	@warning_ignore("integer_division")
	var idx: int = bool_position/8
	var bit: int = 1 << bool_position%8
	bool_position += 1
	return data_array[idx] & bit

func seek_var_pos(position: int) -> void:
	seek(bool_bytes+position)

func get_var_pos() -> int:
	return get_position() - bool_bytes

func jump(amount: int) -> void:
	seek(get_position()+amount)

func put_v2(v2: Vector2) -> void:
	put_float(v2.x)
	put_float(v2.y)

func get_v2() -> Vector2:
	return Vector2(get_float(),get_float())

func put_v3(v3: Vector3) -> void:
	#var bruh := get_position() # Why was this here?
	put_float(v3.x)
	put_float(v3.y)
	put_float(v3.z)

func get_v3() -> Vector3:
	return Vector3(get_float(),get_float(),get_float())

func put_v4(v4: Vector4) -> void:
	put_float(v4.x)
	put_float(v4.y)
	put_float(v4.z)
	put_float(v4.w)
	

func get_v4() -> Vector4:
	return Vector4(
		get_float(),
		get_float(),
		get_float(),
		get_float()
	)

func put_v2i(v2: Vector2i) -> void:
	put_32(v2.x)
	put_32(v2.y)
	

func get_v2i() -> Vector2i:
	return Vector2i(get_32(),get_32())

func put_v3i(v3: Vector3i) -> void:
	put_32(v3.x)
	put_32(v3.y)
	put_32(v3.z)

func get_v3i() -> Vector3i:
	return Vector3i(
		get_32(),
		get_32(),
		get_32()
	)

func put_v4i(v4: Vector4i) -> void:
	put_32(v4.x)
	put_32(v4.y)
	put_32(v4.z)
	put_32(v4.w)
	

func get_v4i() -> Vector4i:
	return Vector4i(
		get_32(),
		get_32(),
		get_32(),
		get_32()
	)

func put_r2(r2: Rect2) -> void:
	put_v2(r2.position)
	put_v2(r2.size)

func get_r2() -> Rect2:
	return Rect2(
		get_float(),
		get_float(),
		get_float(),
		get_float()
	)

func put_r2i(r2i: Rect2i) -> void:
	put_v2i(r2i.position)
	put_v2i(r2i.size)

func get_r2i() -> Rect2i:
	return Rect2i(
		get_32(),
		get_32(),
		get_32(),
		get_32()
	)

func put_quat(quat: Quaternion) -> void:
	put_float(quat.x)
	put_float(quat.y)
	put_float(quat.z)
	put_float(quat.w)
	

func get_quat() -> Quaternion:
	return Quaternion(
		get_float(),
		get_float(),
		get_float(),
		get_float()
	)

func put_color(color: Color) -> void:
	put_float(color.r)
	put_float(color.g)
	put_float(color.b)
	put_float(color.a)

func get_color() -> Color:
	return Color(
		get_float(),
		get_float(),
		get_float(),
		get_float()
	)

func put_udynamic(num: int) -> void:
	if put_eval(num > 255):
		if put_eval(num > 65535):
			if put_eval(num > 4294967295):
				put_u64(num)
			else:
				put_u32(num)
		else:
			put_u16(num)
	else:
		put_u8(num)

func get_udynamic() -> int:
	if get_bool():
		if get_bool():
			if get_bool():
				return get_u64()
			else:
				return get_u32()
		else:
			return get_u16()
	else:
		return get_u8()

func put_dynamic(num: int) -> void:
	if put_eval(num > 127):
		if put_eval(num > 32767):
			if put_eval(num > 2147483647):
				put_64(num)
			else:
				put_32(num)
		else:
			put_16(num)
	else:
		put_8(num)

func get_dynamic() -> int:
	if get_bool():
		if get_bool():
			if get_bool():
				return get_64()
			else:
				return get_32()
		else:
			return get_16()
	else:
		return get_8()

# NOTE / TODO because "1 = 0" these are wasting at least a bit when they're encoded.
# Maybe fix this?

func put_n8(num: float, unit: float = 1.) -> void:
	var frac := clampf(num / unit,0.,1.)
	put_u8(int(255*frac))

func get_n8(unit: float = 1.) -> float:
	var frac := float(get_u8())/255.
	return unit*frac

func put_n16(num: float, unit: float = 1.) -> void:
	var frac := clampf(num / unit,0.,1.)
	put_u16(int(65535*frac))

func get_n16(unit: float = 1.) -> float:
	var frac := float(get_u16())/65535.
	return unit*frac

func put_n32(num: float, unit: float = 1.) -> void:
	var frac := clampf(num / unit,0.,1.)
	put_u32(int(4294967295*frac))

func get_n32(unit: float = 1.) -> float:
	var frac := float(get_u32())/4294967295.
	return unit*frac

func put_n64(num: float, unit: float = 1.) -> void:
	var frac := clampf(num / unit,0.,1.)
	put_u64(int(1.8446744e+19*frac))

func get_n64(unit: float = 1.) -> float:
	var frac := float(get_u64())/1.8446744e+19
	return unit*frac

func put_r8(num: float, unit: float = TAU) -> void:
	var frac := wrapf(num / unit,0.,1.)
	put_u8(int(255*frac))

func get_r8(unit: float = TAU) -> float:
	var frac := float(get_u8())/255.
	return unit*frac

func put_r16(num: float, unit: float = TAU) -> void:
	var frac := wrapf(num / unit,0.,1.)
	put_u16(int(65535*frac))

func get_r16(unit: float = TAU) -> float:
	var frac := float(get_u16())/65535.
	return unit*frac

func put_r32(num: float, unit: float = TAU) -> void:
	var frac := wrapf(num / unit,0.,1.)
	put_u32(int(4294967295*frac))

func get_r32(unit: float = TAU) -> float:
	var frac := float(get_u32())/4294967295.
	return unit*frac

func put_r64(num: float, unit: float = TAU) -> void:
	var frac := wrapf(num / unit,0.,1.)
	put_u64(int(1.8446744e+19*frac))

func get_r64(unit: float = TAU) -> float:
	var frac := float(get_u64())/1.8446744e+19
	return unit*frac

func put_rotation(rot: Vector3) -> void:
	put_r32(rot.x)
	put_r32(rot.y)
	put_r32(rot.z)

func get_rotation() -> Vector3:
	return Vector3(get_r32(),get_r32(),get_r32())

func put_rotation_half(rot: Vector3) -> void:
	put_r16(rot.x)
	put_r16(rot.y)
	put_r16(rot.z)

func get_rotation_half() -> Vector3:
	return Vector3(get_r16(),get_r16(),get_r16())

func put_nv2(v2: Vector2, unit: float = 1.) -> void:
	put_n32(v2.x, unit)
	put_n32(v2.y, unit)

func get_nv2(unit: float) -> Vector2:
	return Vector2(get_n32(unit),get_n32(unit))

func put_rv2_half(v2: Vector2, unit: float = TAU) -> void:
	put_r16(v2.x,unit)
	put_r16(v2.y,unit)

func get_rv2_half(unit: float = TAU) -> Vector2:
	return Vector2(get_r16(unit),get_r16(unit))

func put_nv2_half(v2: Vector2, unit: float = 1.) -> void:
	put_n16(v2.x, unit)
	put_n16(v2.y, unit)

func get_nv2_half(unit: float = 1.) -> Vector2:
	return Vector2(get_n16(unit),get_n16(unit))
