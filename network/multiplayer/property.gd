class_name Property extends Resource

const QuackMultiplayer = preload("res://network/multiplayer/quack_multiplayer.gd")
const NetworkType = QuackMultiplayer.NetworkType
const StreamPeerBitBuffer = preload("res://utils/stream_peer_bit_buffer.gd")
const MultiplayerSession = preload("res://network/multiplayer/multiplayer_session.gd")
const TeamComponent = preload("res://gameplay/team_component.gd")
const OwnerID = preload("res://gameplay/owner_id.gd")
const Serializer = preload("res://gameplay/serializer.gd")

## The exact name of the property, as used in the engine, editor and scripts.
@export var name: StringName
## The exact [member Variant.Type] of the property.
@export var type: Variant.Type
## The maximum precision level the property should use. If the property is above/
## below this threshold, the property will be wrapped when sent over the network.
@export var precision_level: PrecisionLevel
## Which specific property index to send over the network, if applicable.
## (eg, rotation on the x axis exclusively).
@export var sub_property_index: PropertyIndex = PropertyIndex.NONE
## What style of interpolation or value snapping this property should use when
## remote clients receive property updates, especially at rates below the network
## framerate.
@export var interp_type: InterpType = InterpType.INTERPOLATE
## Who this property should be sent to. i.e. everyone needs to see a player's position,
## but not everyone needs to know their health.
@export var visibility_type: VisibilityType = VisibilityType.ALL
## Is this property a "physical" property that should be rewound for hit detection.
## i.e. position, rotation, scale, etc.
@export var physical: bool = false
## IS this property a rotation. Affects how the property is encoded if it is a float.
@export var rotation: bool = false
var network_type: NetworkType
var max_bits: int
var size_bytes: int
var encode_type: NetworkType
@export var value_type: Property
@export var key_type: Property

const ENUM_MAX_BITS = -1

enum PrecisionLevel {
	## Equivalent to a signed 32-bit integer or float. This includes Vectors.
	DEFAULT,# 0, s32
	## Equivalent to a signed 64-bit integer or float. [b]NOTE:[/b] Unless Godot is compiled
	## in 64-bit mode, Vectors will not benefit from the added precision of sending
	## 64-bit numbers.
	MAX,	# 1, s64
	## Equivalent to a signed 16-bit integer or float. This includes Vectors.
	HALF,	# 2, s16
	## Equivalent to a signed 8-bit integer or float. This includes Vectors.
	BYTE,	# 3, s8
	## Equivalent to an unisgned 32-bit integer or float. This includes Vectors.
	u32,	# 4, u32
	## Equivalent to an unsigned 32-bit integer or float. This includes Vectors.
	u64,	# 5, u64
	## Equivalent to an usigned 16-bit integer or float. This includes Vectors.
	u16,	# 6, u16
	## Equivalent to an usigned 8-bit integer or float. This includes Vectors.
	u8,		# 7, u8
	## Dynamically sized integer, depending on how large it is at the time of encoding.
	Dynamic, # 8
	## Dynamically sized unsigned integer, depending on how large it is at the time of encoding.
	uDynamic, # 9
	## This property will be checked, and clamped to its min and maximum enum
	## range values. Hopefully one day this will include Strings, StringNames, etc.
	ENUM,	# 10, Enum (Depends on enum size / range)
}

## What type of interpolation style this property uses.
enum InterpType {
	## Properties with this setting will be interpolated if packets are received
	## slower than the network framerate. (eg, position, velocity, rotation). If
	## Interpolation is unapplicable, this property behaves like [member DISCRETE_PREVIOUS].
	INTERPOLATE,		# 0
	## Properties with this setting will always be discretely updated and snapped
	## to their latest value, even when packets are received slower than the
	## network framerate. (eg, ammunition, health, score).
	DISCRETE_LATEST,	# 1
	## Properties with this setting will always be discretely updated and snapped
	## to their previous value until the latest packet is fully processed. (eg,
	## if visibility is intended to change after a character reaches a certain
	## position, one might use this setting to ensure characters don't disappear
	## too early).
	DISCRETE_PREVIOUS,	# 2
}

enum VisibilityType {
	## Property will always be networked to all players.
	ALL,
	## Property will only be networked to clients who own the node this property
	## describes.
	OWNER_ONLY,
	## Property will only be networked to clients on the same team as the client who
	## owns the node this property describes.
	TEAM_ONLY,
	## Don't ever select this lmao this is for looping while setting up iters in
	## NetworkedNode
	VIS_TYPE_MAX
}

const max_bits_per_level: PackedByteArray = [
	32,
	64,
	16,
	8,
	32,
	64,
	16,
	8,
	ENUM_MAX_BITS
]

enum PropertyIndex {
	NONE = -1,
	X, # 0
	Y, # 1
	Z, # 2
	W, # 3
}

const NO_NODE = -1
const UN_SERIALIZED_NODE = -2
const OBJECT = -3

func _init(name: StringName = &"", type: Variant.Type = TYPE_MAX) -> void:
	if type == TYPE_MAX:
		setup.call_deferred()
		return
	self.name = name
	self.type = type
	assert(!name.is_empty())
	setup()

func setup() -> void:
	# This bit here is fucking stupid lmao
	network_type = QuackMultiplayer.get_net_type(type)
	size_bytes = QuackMultiplayer.get_property_size_by_type(type)
	max_bits = max_bits_per_level[precision_level]
	encode_type = get_encode_type(network_type,sub_property_index,precision_level)
	# Safeguarding against dumb tings
	if not Property.is_interpolatable(type) and interp_type == InterpType.INTERPOLATE:
		if not Engine.is_editor_hint():
			Console.push_warn.call_deferred("Property %s (%s) is of non-interpolatable type %s and is set to interpolate. Changing interp type to discrete latest."%[
				name,resource_path,type_string(type)
			])
		else:
			push_warning("Property %s (%s) is of non-interpolatable type %s and is set to interpolate. Changing interp type to discrete latest."%[
				name,resource_path,type_string(type)
			])
		interp_type = InterpType.DISCRETE_LATEST

static func is_interpolatable(type: Variant.Type) -> bool:
	match type:
		TYPE_INT:
			return true
		TYPE_FLOAT:
			return true
		TYPE_VECTOR2:
			return true
		TYPE_VECTOR3:
			return true
		TYPE_VECTOR4:
			return true
		TYPE_COLOR:
			return true
		TYPE_QUATERNION:
			return true
		TYPE_BASIS:
			return true
		TYPE_TRANSFORM2D:
			return true
		TYPE_TRANSFORM3D:
			return true
		_:
			return false


func _to_string() -> String:
	return "%s %s, network type %s, encode type %s, precision level %s, sub-property index %s, interp type %s, %s"%[
		type_string(type),name,NetworkType.find_key(network_type),
		NetworkType.find_key(encode_type),PrecisionLevel.find_key(precision_level),
		PropertyIndex.find_key(sub_property_index),InterpType.find_key(interp_type),
		"Dynamic number of bits" if size_bytes == QuackMultiplayer.VARIABLE_SIZE or encode_type == NetworkType.TYPE_UDYNAMIC or encode_type == NetworkType.TYPE_SDYNAMIC else "1 bit" if size_bytes == QuackMultiplayer.BOOL_OFFSET else "%s bits"%(size_bytes*8)
	]

func get_property(node: Object) -> Variant:
	match encode_type:
		NetworkType.TYPE_OBJECT:
			return Property.node_to_property(node[name] as Object)
		NetworkType.TYPE_ARRAY:
			var casted := node[name] as Array
			var size := casted.size()
			var array := []
			array.resize(size)
			if value_type.encode_type == NetworkType.TYPE_OBJECT:
				for i in size:
					array[i] = Property.node_to_property(casted[i] as Object)
			else:
				for i in size:
					array[i] = casted[i]
			return array
		_:
			if sub_property_index > PropertyIndex.NONE:
				return node[name][sub_property_index]
			else:
				return node[name]

static func property_to_node(property: int) -> Node:
	if property < 0:
		return null
	else:
		return Serializer.uid_map[property as int].owner

static func node_to_property(node: Object) -> int:
	if node == null or not is_instance_valid(node):
		return NO_NODE
	elif node is Node:
		if Serializer.component_list.has(node):
			return Serializer.component_list[node as Node].uid
		else:
			return UN_SERIALIZED_NODE
	else:
		return OBJECT

func set_property(property: Variant, node: Object) -> void:
	match encode_type:
		NetworkType.TYPE_OBJECT:
			node[name] = Property.property_to_node(property as int)
		NetworkType.TYPE_ARRAY:
			var casted := property as Array
			var size := casted.size()
			var node_array := node[name] as Array
			node_array.resize(size)
			if value_type.encode_type == NetworkType.TYPE_OBJECT:
				for i in size:
					node_array[i] = Property.property_to_node(casted[i] as int)
			else:
				for i in size:
					node_array[i] = property
		_:
			if sub_property_index > PropertyIndex.NONE:
				node[name][sub_property_index] = property
			else:
				node[name] = property

func set_property_interpolated(property: Variant, node: Object, weight: float) -> void:
	match interp_type:
		InterpType.INTERPOLATE:
			set_property(lerp(get_property(node),property,weight),node)
		InterpType.DISCRETE_LATEST:
			set_property(property,node)
		InterpType.DISCRETE_PREVIOUS:
			if is_equal_approx(weight,1.):
				set_property(property,node)

#func get_property_indexed(property: Variant) -> Variant:
	#if sub_property_index > PropertyIndex.NONE:
		#return property[sub_property_index]
	#else:
		#return property

static func get_visibility(node_owner_id: int, node_team: int, receiver_id: int, hostility_mask: int) -> VisibilityType:
	if receiver_id == 0 or receiver_id == node_owner_id:
		return VisibilityType.OWNER_ONLY
	elif TeamComponent.teams_are_friendly(node_team,hostility_mask):
		return VisibilityType.TEAM_ONLY
	else:
		return VisibilityType.ALL

static func get_visibility_by_clients(owner_id: int, receiver_id: int) -> VisibilityType:
	if receiver_id == 0 or receiver_id == owner_id:
		return VisibilityType.OWNER_ONLY
	elif MultiplayerSession.are_clients_friendly(owner_id,receiver_id):
		return VisibilityType.TEAM_ONLY
	else:
		return VisibilityType.ALL

static func get_visibility_by_team(owner_id: int, owner_team: int, receiver_id: int) -> VisibilityType:
	if receiver_id == 0 or receiver_id == owner_id:
		return VisibilityType.OWNER_ONLY
	elif TeamComponent.teams_are_friendly(owner_team,MultiplayerSession.clients[receiver_id].team):
		return VisibilityType.TEAM_ONLY
	else:
		return VisibilityType.ALL

static func get_visibility_by_node(node: Node, receiver_id: int, hostility_mask: int) -> VisibilityType:
	# Not extensible for other players
	if receiver_id == 0 or OwnerID.get_node_owner_id(node) == receiver_id:
		return VisibilityType.OWNER_ONLY
	elif TeamComponent.teams_are_friendly(TeamComponent.get_node_team_id(node),hostility_mask):
		return VisibilityType.TEAM_ONLY
	else:
		return VisibilityType.ALL

func get_visible(owner_id: int, receiver_id: int) -> bool:
	if receiver_id == 0:
		return true
	match visibility_type:
		VisibilityType.ALL:
			return true
		VisibilityType.OWNER_ONLY:
			return owner_id == receiver_id
		VisibilityType.TEAM_ONLY:
			return MultiplayerSession.are_clients_friendly(owner_id,receiver_id)
		_:
			Console.get_assertfail_msg(false,"Wtf lmao")
			return false

func encode(property: Variant, buffer: StreamPeerBitBuffer) -> void:
	# NOTE: Don't need to check for sub property indexes here because it's checked
	# ahead of time when setting up encode_type
	#Console.write("%s Getting property %s (%s)"%[
		#MultiplayerSession.frame_num,
		#name,
		#property
	#])
	match encode_type:
		NetworkType.TYPE_BOOL:
			buffer.put_bool(property)
		NetworkType.TYPE_INT:
			buffer.put_32(property)
		NetworkType.TYPE_FLOAT:
			if rotation:
				buffer.put_r32(property)
			else:
				buffer.put_float(property)
		NetworkType.TYPE_VECTOR2:
			buffer.put_v2(property)
		NetworkType.TYPE_VECTOR2I:
			buffer.put_v2i(property)
		NetworkType.TYPE_RECT2:
			buffer.put_r2(property)
		NetworkType.TYPE_RECT2I:
			buffer.put_r2i(property)
		NetworkType.TYPE_QUATERNION:
			buffer.put_quat(property)
		NetworkType.TYPE_COLOR:
			buffer.put_color(property)
		NetworkType.TYPE_VECTOR3:
			if rotation:
				if precision_level == PrecisionLevel.HALF:
					buffer.put_rotation_half(property)
				else:
					buffer.put_rotation(property)
			else:
				buffer.put_v3(property)
		NetworkType.TYPE_VECTOR3I:
			buffer.put_v3i(property)
		NetworkType.TYPE_VECTOR4:
			buffer.put_v4(property)
		NetworkType.TYPE_VECTOR4I:
			buffer.put_v4i(property)
		NetworkType.TYPE_U8:
			buffer.put_u8(property)
		NetworkType.TYPE_S8:
			buffer.put_8(property)
		NetworkType.TYPE_U16:
			buffer.put_u16(property)
		NetworkType.TYPE_S16:
			buffer.put_16(property)
		NetworkType.TYPE_U32:
			buffer.put_u32(property)
		NetworkType.TYPE_U64:
			buffer.put_u64(property)
		NetworkType.TYPE_S64:
			buffer.put_64(property)
		NetworkType.TYPE_DOUBLE:
			buffer.put_double(property)
		NetworkType.TYPE_HALF:
			buffer.put_half(property)
		NetworkType.TYPE_UDYNAMIC:
			buffer.put_udynamic(property)
		NetworkType.TYPE_SDYNAMIC:
			buffer.put_dynamic(property)
		NetworkType.TYPE_OBJECT:
			buffer.put_dynamic(property) # UID
			# NOTE this would encode the property if the value passed was actually
			# an object
			#if property == null or not is_instance_valid(property):
				#buffer.put_32(NO_NODE)
			#if property is Node:
				#if Serializer.component_list.has(property):
					#buffer.put_32(Serializer.component_list[property].uid)
				#else:
					#buffer.put_32(UN_SERIALIZED_NODE)
			#else:
				#buffer.put_32(OBJECT)
		NetworkType.TYPE_ARRAY:
			var casted := property as Array
			var size := casted.size()
			buffer.put_udynamic(size)
			for i in size:
				value_type.encode(casted[i],buffer)
		_:
			assert(QuackMultiplayer.NetworkTypeAssertLmao.has(encode_type), "Variant type %s is not a valid network type."%encode_type)
			#if encode_type == NetworkType.TYPE_PACKED_BYTE_ARRAY:
				#Console.writevar.call_deferred(buffer)
				#Console.writevar.call_deferred(buffer.data_array.slice(buffer.get_position(),buffer.get_position()+100))
			buffer.put_var(property)

func decode(buffer: StreamPeerBitBuffer) -> Variant:
	#Console.write("%s Setting property %s"%[
		#MultiplayerSession.frame_num,
		#name,
	#])
	match encode_type:
		NetworkType.TYPE_BOOL:
			return buffer.get_bool()
		NetworkType.TYPE_INT:
			return buffer.get_32()
		NetworkType.TYPE_FLOAT:
			if rotation:
				return buffer.get_r32()
			else:
				return buffer.get_float()
		NetworkType.TYPE_VECTOR2:
			return buffer.get_v2()
		NetworkType.TYPE_VECTOR2I:
			return buffer.get_v2i()
		NetworkType.TYPE_RECT2:
			return buffer.get_r2()
		NetworkType.TYPE_RECT2I:
			return buffer.get_r2i()
		NetworkType.TYPE_QUATERNION:
			return buffer.get_quat()
		NetworkType.TYPE_COLOR:
			buffer.get_color()
		NetworkType.TYPE_VECTOR3:
			if rotation:
				if precision_level == PrecisionLevel.HALF:
					return buffer.get_rotation_half()
				else:
					return buffer.get_rotation()
			else:
				return buffer.get_v3()
		NetworkType.TYPE_VECTOR3I:
			return buffer.get_v3i()
		NetworkType.TYPE_VECTOR4:
			return buffer.get_v4()
		NetworkType.TYPE_VECTOR4I:
			return buffer.get_v4i()
		NetworkType.TYPE_U8:
			return buffer.get_u8()
		NetworkType.TYPE_S8:
			return buffer.get_8()
		NetworkType.TYPE_U16:
			return buffer.get_u16()
		NetworkType.TYPE_S16:
			return buffer.get_16()
		NetworkType.TYPE_U32:
			return buffer.get_u32()
		NetworkType.TYPE_U64:
			return buffer.get_u64()
		NetworkType.TYPE_S64:
			return buffer.get_64()
		NetworkType.TYPE_DOUBLE:
			return buffer.get_double()
		NetworkType.TYPE_HALF:
			return buffer.get_half()
		NetworkType.TYPE_UDYNAMIC:
			return buffer.get_udynamic()
		NetworkType.TYPE_SDYNAMIC:
			return buffer.get_dynamic()
		NetworkType.TYPE_OBJECT:
			return buffer.get_dynamic() # UID
		NetworkType.TYPE_ARRAY:
			var size := buffer.get_udynamic()
			var array: Array
			array.resize(size)
			for i in size:
				array[i] = value_type.decode(buffer)
			return array
		_:
			assert(QuackMultiplayer.NetworkTypeAssertLmao.has(encode_type), "Variant type %s is not a valid network type."%encode_type)
			return buffer.get_var()
	return null

static func get_encode_type(type: NetworkType, sub_property_index: PropertyIndex, precision_level: PrecisionLevel) -> NetworkType:
	match type:
		NetworkType.TYPE_BOOL:
			return NetworkType.TYPE_BOOL
		NetworkType.TYPE_INT:
			match precision_level:
					PrecisionLevel.DEFAULT:
						return NetworkType.TYPE_INT
					PrecisionLevel.MAX:
						return NetworkType.TYPE_S64
					PrecisionLevel.HALF:
						return NetworkType.TYPE_S16
					PrecisionLevel.BYTE:
						return NetworkType.TYPE_S8
					PrecisionLevel.u32:
						return NetworkType.TYPE_U32
					PrecisionLevel.u64:
						return NetworkType.TYPE_U64
					PrecisionLevel.u16:
						return NetworkType.TYPE_U16
					PrecisionLevel.u8:
						return NetworkType.TYPE_U8
					PrecisionLevel.Dynamic:
						return NetworkType.TYPE_SDYNAMIC
					PrecisionLevel.uDynamic:
						return NetworkType.TYPE_UDYNAMIC
					PrecisionLevel.ENUM:
						return NetworkType.TYPE_ENUM
		NetworkType.TYPE_FLOAT:
			match precision_level:
					PrecisionLevel.DEFAULT:
						return NetworkType.TYPE_FLOAT
					PrecisionLevel.MAX:
						return NetworkType.TYPE_DOUBLE
					PrecisionLevel.HALF:
						return NetworkType.TYPE_HALF
		NetworkType.TYPE_VECTOR2:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_FLOAT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_VECTOR2
		NetworkType.TYPE_VECTOR2I:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_INT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_VECTOR2
		NetworkType.TYPE_RECT2:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_FLOAT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_RECT2
		NetworkType.TYPE_RECT2I:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_INT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_RECT2I
		NetworkType.TYPE_QUATERNION:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_FLOAT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_QUATERNION
		NetworkType.TYPE_COLOR:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_FLOAT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_COLOR
		NetworkType.TYPE_VECTOR3:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_FLOAT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_VECTOR3
		NetworkType.TYPE_VECTOR3I:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_INT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_VECTOR3I
		NetworkType.TYPE_VECTOR4:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_FLOAT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_VECTOR4
		NetworkType.TYPE_VECTOR4I:
			if sub_property_index > PropertyIndex.NONE:
				return get_encode_type(NetworkType.TYPE_INT,sub_property_index,precision_level)
			else:
				return NetworkType.TYPE_VECTOR4I
		_:
			assert(QuackMultiplayer.NetworkTypeAssertLmao.has(type), "Variant type %s is not a valid network type."%type)
			return type
	return NetworkType.TYPE_NIL

static func name_to_precision(name: String) -> PrecisionLevel:
	
	# 8 bit
	if name.begins_with(QuackMultiplayer.u8_prefix):
		return PrecisionLevel.u8
	if name.begins_with(QuackMultiplayer.s8_prefix):
		return PrecisionLevel.BYTE
	
	# 16 bit
	if name.begins_with(QuackMultiplayer.u16_prefix):
		return PrecisionLevel.u16
	if name.begins_with(QuackMultiplayer.s16_prefix) or name.begins_with(QuackMultiplayer.half_prefix):
		return PrecisionLevel.HALF
	
	# 32 bit
	if name.begins_with(QuackMultiplayer.u32_prefix):
		return PrecisionLevel.u32
	# default lmao
#	if name.begins_with(s32_prefix):
#		pass
	
	# 64 bit
	if name.begins_with(QuackMultiplayer.u64_prefix):
		return PrecisionLevel.u64
	if name.begins_with(QuackMultiplayer.s64_prefix) or name.begins_with(QuackMultiplayer.double_prefix):
		return PrecisionLevel.MAX
	
	# Dynamic number of bits
	if name.begins_with(QuackMultiplayer.dynamic_prefix):
		return PrecisionLevel.Dynamic
	if name.begins_with(QuackMultiplayer.udynamic_prefix):
		return PrecisionLevel.uDynamic
	
	# base case, signed 32-bit
	return PrecisionLevel.DEFAULT
