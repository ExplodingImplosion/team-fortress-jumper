const QuackMultiplayer = preload("res://network/multiplayer/quack_multiplayer.gd") # lmao
const ByteUtils = Quack.ByteUtils
const net_prefix: String = "net_"
const u8_prefix = "u8_"
const s8_prefix = "s8_"
const u16_prefix = "u16_"
const s16_prefix = "s16_"
const u32_prefix = "u32_"
#const s32_prefix = "s32_" # default int
const u64_prefix = "u64_"
const s64_prefix = "s64_"
const double_prefix = "double_"
const half_prefix = "half_"
const dynamic_prefix = "d_"
const udynamic_prefix = "ud_"
const net_updated_this_frame = &"net_updated_this_frame"
const net_predicted_locally = &"net_predicted_locally"
const net_u32_owner_id = &"net_u32_owner_id"

static var scene_registry: Dictionary[String,int]
static var scenes: Array[PackedScene]
static var ready: bool = false

static func register_scene(path: String, idx: int) -> void:
	var scene: PackedScene = load(path) as PackedScene
	scene_registry[scene.resource_path] = idx
	scenes[idx] = scene
	Quack.tree.physics_frame.connect(evaluate_ready,CONNECT_REFERENCE_COUNTED)

static func evaluate_ready() -> void:
	for scene in scenes:
		if scene == null:
			return
	ready = true
	while Quack.tree.physics_frame.is_connected(evaluate_ready):
		Quack.tree.physics_frame.disconnect(evaluate_ready)

static func register_scenes() -> void:
	#var threaded_scene_registry: bool = ProjectSettings.get_setting_safe("quack/debug/threaded_scene_registry",true) as bool
	var scene_paths := get_scene_paths()
	scenes.resize(scene_paths.size())
	for i in scene_paths.size():
		# Dont do threaded scene registry stuff anymore
		#if threaded_scene_registry:
			#if OS.is_stdout_verbose():
				#Quack.ThreadUtils.add_thread(Quack.TimeUtils.check_func_time.bind(register_scene.bind(scene_paths[i],i)))
			#else:
				#Quack.ThreadUtils.add_thread(register_scene.bind(scene_paths[i],i))
		#else:
			register_scene(scene_paths[i],i)

const GAMEPLAY_DIRECTORY = "res://gameplay"
static func get_scene_paths(path: String = GAMEPLAY_DIRECTORY) -> PackedStringArray:
	var scene_paths: PackedStringArray = []
	for file in DirAccess.get_files_at(path):
		file = file.trim_suffix(".remap")
		if file.get_extension() == "tscn":
			Console.writeverb.call_deferred("Found scene %s."%file)
			scene_paths.append(path+"/"+file)
	
	for folder in DirAccess.get_directories_at(path):
		scene_paths.append_array(get_scene_paths(path+"/"+folder))
	
	return scene_paths

static func register_all_scripts() -> void:
	var scripts: Array[Dictionary] = ProjectSettings.get_global_class_list()
	for script_info: Dictionary in scripts:
		var script: Script = load(script_info.path)
		if script == QuackMultiplayer:
			continue
		var property_list: Array[Dictionary] = script.get_script_property_list()
		var is_networked: bool
		var property_names: Array[StringName] = []
		var property_types: PackedByteArray = []
		for property_info: Dictionary in property_list:
			if is_net_updated_this_frame(property_info):
				is_networked = true
			elif is_valid_net_var(property_info):
				add_networked_property(property_info,property_names,property_types)
		if is_networked:
			var predicted: bool = is_script_predicted(script)
			Console.push_warn.call_deferred("QuackMultiplayer would normally add a networked node type to Resources here")
			# Resources.networked_node_types[script.get_instance_id()] = NetworkedNode.new(property_names,property_types,predicted)#,property_types)
	#Resources.add_pools_to_networked_nodes()
	Console.push_warn.call_deferred("QuackMultiplayer would normally add scenes to networked nodes in Resources here")
	#Resources.add_scenes_to_networked_nodes()

static func add_networked_property(property_info: Dictionary, property_names: Array[StringName], property_types: PackedByteArray) -> void:
	property_names.append(property_info.name)
	ByteUtils.assert_valid_u8(property_info.type)
	property_types.append(get_net_var_type(property_info))

static func is_script_predicted(script: Script) -> bool:
	# could also just be
#	return script.get_script_constant_map().has(net_predicted_locally)
	var constant_map: Dictionary = script.get_script_constant_map()
	if constant_map.has(net_predicted_locally):
		return constant_map[net_predicted_locally]
	return false

static func get_net_var_type(property_info: Dictionary) -> int:
	return get_property_type(property_info.name,property_info.type)

static func get_property_type(name: String, type: Variant.Type) -> int:
	if type == TYPE_INT:
		return get_int_type(name)
	if type == TYPE_FLOAT:
		return get_float_type(name)
	return type

static func get_int_type(name: String) -> NetworkType:
	
	name = name.trim_prefix(net_prefix)
	
	# 8 bit
	if name.begins_with(u8_prefix):
		return NetworkType.TYPE_U8
	if name.begins_with(s8_prefix):
		return NetworkType.TYPE_S8
	
	# 16 bit
	if name.begins_with(u16_prefix):
		return NetworkType.TYPE_U16
	if name.begins_with(s16_prefix):
		return NetworkType.TYPE_S16
	
	# 32 bit
	if name.begins_with(u32_prefix):
		return NetworkType.TYPE_U32
	# default lmao
#	if name.begins_with(s32_prefix):
#		pass
	
	# 64 bit
	if name.begins_with(u64_prefix):
		return NetworkType.TYPE_U64
	if name.begins_with(s64_prefix):
		return NetworkType.TYPE_S64
	
	# base case, signed 32-bit
	return NetworkType.TYPE_S32

static func get_float_type(name: String) -> NetworkType:
	name = name.trim_prefix(net_prefix)
	if name.begins_with(double_prefix):
		return NetworkType.TYPE_DOUBLE
	if name.begins_with(half_prefix):
		return NetworkType.TYPE_HALF
	return NetworkType.TYPE_FLOAT

static func is_script_variable(property_info: Dictionary) -> bool:
	return property_info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE

static func is_net_updated_this_frame(property_info: Dictionary) -> bool:
	return is_script_variable(property_info) and property_info.name == net_updated_this_frame

static func is_valid_net_var(property_info: Dictionary) -> bool:
	return is_script_variable(property_info) and property_info.name.begins_with(net_prefix) and not property_info.name == net_predicted_locally

static func set_node_position_on_ready(node: Node3D, position: Vector3) -> void:
	node.ready.connect(node.set_global_position.bind(position),CONNECT_ONE_SHOT)

static func set_node_position_on_tree_entered(node: Node3D, position: Vector3) -> void:
	node.tree_entered.connect(node.set_global_position.bind(position),CONNECT_ONE_SHOT)

static func set_node_rotation_on_ready(node: Node3D, rotation: Vector3) -> void:
	node.ready.connect(node.set_global_rotation.bind(rotation),CONNECT_ONE_SHOT)

static func set_node_rotation_on_tree_entered(node: Node3D, rotation: Vector3) -> void:
	node.tree_entered.connect(node.set_global_rotation.bind(rotation),CONNECT_ONE_SHOT)

# ok lowkey maybe just use Transform3D instead lololol
static func set_node_transform_on_ready(node: Node3D, position: Vector3, rotation: Vector3) -> void:
	set_node_position_on_ready(node,position)
	set_node_rotation_on_ready(node,rotation)

# ok lowkey maybe just use Transform3D instead lololol
static func set_node_transform_on_tree_entered(node: Node3D, position: Vector3, rotation: Vector3) -> void:
	set_node_position_on_tree_entered(node,position)
	set_node_rotation_on_tree_entered(node,rotation)

const BOOL_OFFSET = -1
const VARIABLE_SIZE = -2

static var NetworkTypeAssertLmao: Dictionary[int,String] = (func() -> Dictionary[int,String]:
	var typeassertlmao: Dictionary[int,String] = {}
	for type in NetworkType.keys():
		typeassertlmao[NetworkType[type]] = type
	return typeassertlmao).call() as Dictionary[int,String]
enum NetworkType {
	TYPE_NIL, # 0
	TYPE_INT, # 1
	INT_FLAG = 1, # 1
	TYPE_FLOAT, # 2
	FLOAT_FLAG = 2, # 2
	TYPE_BOOL = 0b100, # 4
	TYPE_STRING = 0b1000, # 8
	TYPE_VECTOR2 = 0b110, # 6, has float flag
	TYPE_VECTOR2I = 0b101, # 5, has int flag
	TYPE_RECT2 = 0b1010, # 10, has float flag
	TYPE_RECT2I = 0b1001, # 9, has int flag
	TYPE_VECTOR3 = 0b1110, # 14, has float flag
	TYPE_VECTOR3I = 0b1101, # 13, has int flag
	TYPE_TRANSFORM2D = 0b10010, # 18, has float flag
	TYPE_VECTOR4 = 0b11010, # 26, has float flag
	TYPE_VECTOR4I = 0b10001, # 17, has int flag
	TYPE_PLANE = 0b11110, # 30, has float flag
	TYPE_QUATERNION = 0b100010, # 34, has float flag
	TYPE_QUAT = 0b100010, # 34, has float flag
	TYPE_BASIS = 0b100110, # 38, has float flag
	TYPE_TRANSFORM3D = 0b101010, # 42, has float flag
	TYPE_PROJECTION = 0b101110, # 46, has float flag
	TYPE_COLOR = 0b110010, # 50, has float flag
	TYPE_COLORI = 0b10101, # 21, has int flag
	TYPE_STRING_NAME = 0b1100, # 12
	TYPE_NODE_PATH = 0b10000, # 16
	TYPE_RID = 0b11000, # 24
	TYPE_OBJECT = 0b11100, # 28
	TYPE_CALLABLE = 0b100000, # 32
	TYPE_SIGNAL = 0b100100, # 36
	TYPE_DICTIONARY = 0b101000, # 40
	TYPE_DICT = 0b101000, # 40
	TYPE_ARRAY = 0b101100, # 44
	TYPE_PACKED_BYTE_ARRAY = 0b110000, # 48
	TYPE_PACKED_INT32_ARRAY = 0b110100, # 52
	TYPE_PACKED_INT64_ARRAY = 0b111000, # 56
	TYPE_PACKED_FLOAT32_ARRAY = 0b111100, # 60
	TYPE_PACKED_FLOAT64_ARRAY = 0b1000000, # 64
	TYPE_PACKED_STRING_ARRAY = 0b1000100, # 68
	TYPE_PACKED_VECTOR2_ARRAY = 0b1001000, # 72
	TYPE_PACKED_VECTOR3_ARRAY = 0b1001100, # 76
	TYPE_PACKED_COLOR_ARRAY = 0b1010000, # 80
	TYPE_PACKED_VECTOR4_ARRAY = 0b1010100, # 84
	TYPE_U8 = 0b11101, # 29, has int flag
	TYPE_S8 = 0b100001, # 33, has int flag
	TYPE_U16 = 0b100101, # 37, has int flag
	TYPE_S16 = 0b101001, # 41, has int flag
	TYPE_U32 = 0b101101, # 45, has int flag
	TYPE_S32 = 1,
	TYPE_U64 = 0b110001, # 49, has int flag
	TYPE_S64 = 0b110101, # 53, has int flag
	TYPE_UDYNAMIC = 0b111001, # 57, has int flag
	TYPE_SDYNAMIC = 0b111101, # 61, has int flag
	TYPE_DOUBLE = 0b110110, # 54, has float flag
	TYPE_HALF = 0b111010, # 58, has float flag
	TYPE_ENUM = 0b111001 # 57, has int flag
}

static func get_net_type(type: Variant.Type) -> NetworkType:
	match type:
		TYPE_NIL:
			return NetworkType.TYPE_NIL
		TYPE_INT:
			return NetworkType.TYPE_INT
		TYPE_FLOAT:
			return NetworkType.TYPE_FLOAT
		TYPE_BOOL:
			return NetworkType.TYPE_BOOL
		TYPE_STRING:
			return NetworkType.TYPE_STRING
		TYPE_VECTOR2:
			return NetworkType.TYPE_VECTOR2
		TYPE_VECTOR2I:
			return NetworkType.TYPE_VECTOR2I
		TYPE_RECT2:
			return NetworkType.TYPE_RECT2
		TYPE_RECT2I:
			return NetworkType.TYPE_RECT2I
		TYPE_VECTOR3:
			return NetworkType.TYPE_VECTOR3
		TYPE_VECTOR3I:
			return NetworkType.TYPE_VECTOR3I
		TYPE_TRANSFORM2D:
			return NetworkType.TYPE_TRANSFORM2D
		TYPE_VECTOR4:
			return NetworkType.TYPE_VECTOR4
		TYPE_VECTOR4I:
			return NetworkType.TYPE_VECTOR4I
		TYPE_PLANE:
			return NetworkType.TYPE_PLANE
		TYPE_QUATERNION:
			return NetworkType.TYPE_QUATERNION
		TYPE_BASIS:
			return NetworkType.TYPE_BASIS
		TYPE_TRANSFORM3D:
			return NetworkType.TYPE_TRANSFORM3D
		TYPE_PROJECTION:
			return NetworkType.TYPE_PROJECTION
		TYPE_COLOR:
			return NetworkType.TYPE_COLOR
		TYPE_STRING_NAME:
			return NetworkType.TYPE_STRING_NAME
		TYPE_NODE_PATH:
			return NetworkType.TYPE_NODE_PATH
		TYPE_RID:
			return NetworkType.TYPE_RID
		TYPE_OBJECT:
			return NetworkType.TYPE_OBJECT
		TYPE_CALLABLE:
			return NetworkType.TYPE_CALLABLE
		TYPE_SIGNAL:
			return NetworkType.TYPE_SIGNAL
		TYPE_DICTIONARY:
			return NetworkType.TYPE_DICTIONARY
		TYPE_ARRAY:
			return NetworkType.TYPE_ARRAY
		TYPE_PACKED_BYTE_ARRAY:
			return NetworkType.TYPE_PACKED_BYTE_ARRAY
		TYPE_PACKED_INT32_ARRAY:
			return NetworkType.TYPE_PACKED_INT32_ARRAY
		TYPE_PACKED_INT64_ARRAY:
			return NetworkType.TYPE_PACKED_INT64_ARRAY
		TYPE_PACKED_FLOAT32_ARRAY:
			return NetworkType.TYPE_PACKED_FLOAT32_ARRAY
		TYPE_PACKED_FLOAT64_ARRAY:
			return NetworkType.TYPE_PACKED_FLOAT64_ARRAY
		TYPE_PACKED_STRING_ARRAY:
			return NetworkType.TYPE_PACKED_STRING_ARRAY
		TYPE_PACKED_VECTOR2_ARRAY:
			return NetworkType.TYPE_PACKED_VECTOR2_ARRAY
		TYPE_PACKED_VECTOR3_ARRAY:
			return NetworkType.TYPE_PACKED_VECTOR3_ARRAY
		TYPE_PACKED_COLOR_ARRAY:
			return NetworkType.TYPE_PACKED_COLOR_ARRAY
		TYPE_PACKED_VECTOR4_ARRAY:
			return NetworkType.TYPE_PACKED_VECTOR4_ARRAY
		TYPE_MAX:
			Console.get_assertfail_msg(false,"Invalid type %s supplied."%type_string(type))
		_:
			Console.get_assertfail_msg(false,"Invalid type %s supplied."%type_string(type))
	return NetworkType.TYPE_NIL

static func is_int_type(type: NetworkType) -> bool:
	return type & NetworkType.INT_FLAG

static func is_float_type(type: NetworkType) -> bool:
	return type & NetworkType.FLOAT_FLAG

static func is_non_numerical(type: NetworkType) -> bool:
	return not ( is_int_type(type) or is_float_type(type) )

static func get_property_size_by_type(type: Variant.Type) -> int:
	match type:
		TYPE_BOOL:
			return BOOL_OFFSET
		TYPE_INT:
			return 4
		TYPE_FLOAT:
			return 4
		TYPE_VECTOR2:
			return 8
		TYPE_VECTOR2I:
			return 8
		TYPE_RECT2:
			return 8
		TYPE_RECT2I:
			return 8
		TYPE_QUATERNION:
			return 16
		TYPE_COLOR:
			return 16
		TYPE_VECTOR3:
			return 12
		TYPE_VECTOR3I:
			return 12
		TYPE_VECTOR4:
			return 16
		TYPE_VECTOR4I:
			return 16
		#TYPE_NET_U8:
			#return 1
		#TYPE_NET_S8:
			#return 1
		#TYPE_NET_U16:
			#return 2
		#TYPE_NET_S16:
			#return 2
		#TYPE_NET_U32:
			#return 4
		#TYPE_NET_U64:
			#return 8
		#TYPE_NET_S64:
			#return 8
		#TYPE_NET_DOUBLE:
			#return 8
		#TYPE_NET_HALF:
			#return 2
		_:
			assert(type < TYPE_MAX and type > -1, "Variant type %s is of an invalid type type. Valid types are between 0 and %s."%[type,TYPE_MAX-1])
			return VARIABLE_SIZE
	return VARIABLE_SIZE
