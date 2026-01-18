@tool
class_name NetworkedNode extends Resource

const QuackMultiplayer = preload("res://network/multiplayer/quack_multiplayer.gd")
const StreamPeerBitBuffer = preload("res://utils/stream_peer_bit_buffer.gd")
const VisType = Property.VisibilityType

## Set to true after [method setup] is finished.
var ready: bool = false
## Set to true if the networked node is functioning as a scene owner (i.e. has
## spawn and deletion bits)
var owner: bool = false
## Set up as scene path if the node is functioning as a scene owner ([member owner]
## is set to true, and this networked node is describing a specific instantiable
## scene.)
var owner_scene_path: String = ""
var num_props: int
## Optional script to include that enables the editor to pull variables from the
## script for networking.
@export var source_script: Script
## Required if [member source_script] is blank, enables the editor to pull variables
## from the base class for networking.
@export var base_class: StringName
## List of [Property]s that will be networked.
@export var properties: Array[Property]
var iter_all: PackedByteArray
var iter_owner_only: PackedByteArray
var iter_team_only: PackedByteArray
var iter_physical: PackedByteArray
# NOTE: This is a bit less extensible because if owner only and team only order
# is changed then this doesnt automatically reflect that since its just an array
var iters: Array[PackedByteArray] = [iter_all,iter_owner_only,iter_team_only]
var iters_visible: Array[bool]
var bitmask_map: Dictionary[PackedByteArray,int]
var is_fixed_size: bool = true
var num_bools: int = 0
var fixed_size_bytes: int = 0

const node_changed = true
const node_unchanged = false

const node_delta = true
const node_not_delta = false

const node_spawned = true
const node_not_spawned = false

const node_deleted = false # NOTE This is correct and on purpose

const property_changed = true
const property_unchanged = false

enum StatusFlags {
	STATUS_FLAGS_NONE = 0,
	UPDATE = 1<<0,
	DELTA = 1<<1,
	SPAWN = 1<<2,
	DELETE = 0,
	UpdateBit = 0,
	DeltaBit = 1,
	SpawnBit = 2,
	
	DELTA_NODE = UPDATE | DELTA,
	SPAWN_NODE = UPDATE | SPAWN,
	DELETE_NODE = UPDATE | DELETE,
}

func _to_string() -> String:
	var string := "Source script:	%s
Base class:		%s
Properties:\n\t"%[source_script,base_class]
	string += "\n\t".join(properties)
	return string

func _init() -> void:
	if !Engine.is_editor_hint():
		setup.call_deferred()

## Called once on [method _init] after being deferred.
func setup() -> void:
	var pmap := get_property_list_map(source_script) if source_script else get_property_list_map_by_base_type(base_class)
	for prop in properties:
		@warning_ignore("incompatible_ternary")
		assert(pmap.has(prop.name),"Property %s isn't in %s' property list."%[prop.name,source_script.resource_path if source_script else base_class])
		assert(pmap[prop.name].type == prop.type, "Property %s is %s type in resource but %s type in property list."%[
			prop.name,prop.type,pmap[prop.name].type
		])
		if prop.size_bytes > 0:
			fixed_size_bytes += prop.size_bytes
		elif prop.size_bytes == QuackMultiplayer.VARIABLE_SIZE:
			is_fixed_size = false
			# idk do something lmao
		elif prop.type == TYPE_BOOL:
			num_bools += 1
		else:
			Console.get_assertfail_msg(false,"Bruh invalid property lmao",true)
	
	num_props = properties.size()
	var vis_type: VisType
	var property: Property
	for i in num_props:
		property = properties[i]
		if property.physical:
			iter_physical.append(i)
			# If this property is only intended to be rewound, never encode it.
			if property.recent_only:
				continue
			
		iter_owner_only.append(i)
		vis_type = property.visibility_type
		if vis_type != VisType.OWNER_ONLY:
			iter_team_only.append(i)
			if vis_type == VisType.ALL:
				iter_all.append(i)
		# Older version
		#match property.visibility_type:
			#VisType.ALL:
				#iter_all.append(i)
				## When encoding for everyone, friendlies will still use their
				## team iterator, so append index to team only iterator too
				#iter_team_only.append(i)
			#VisType.TEAM_ONLY:
				#iter_team_only.append(i)
	iters_visible.resize(VisType.VIS_TYPE_MAX)
	for i in VisType.VIS_TYPE_MAX:
		iters_visible[i] = not iters[i].is_empty()
	iters.make_read_only()
	
	#setup_bitmask_map()
	ready = true

static func get_full_property_list(script: Script) -> Array[Dictionary]:
	var property_list := ClassDB.class_get_property_list(script.get_instance_base_type())
	property_list.append_array(script.get_script_property_list())
	return property_list

static func get_property_list_map(script: Script) -> Dictionary[StringName,Dictionary]:
	var map: Dictionary[StringName,Dictionary] = {}
	var plist := get_full_property_list(script)
	for p in plist:
		map[p.name] = p
	return map

static func get_property_list_map_by_base_type(type: StringName) -> Dictionary[StringName,Dictionary]:
	var map: Dictionary[StringName,Dictionary] = {}
	var plist: Array[Dictionary] = ClassDB.class_get_property_list(type)
	for p in plist:
		map[p.name] = p
	return map

## Checks the [member source_script] if valid, and checks the script's base class
## (if [member source_script] is not defined, then the base class is pulled from
## [member base_class]). Converts all script and class variables to [Property]s
## and appends them to [member properties].
@export_tool_button("check plist") var get_plist_func := func get_plist() -> void:
	if not source_script and not base_class:
		printerr("Can't get a property list when there's no base class or source script"); return
	var property_list := get_full_property_list(source_script) if source_script else ClassDB.class_get_property_list(base_class)
	var potential_properties: Array[Property]
	for p in property_list:
		if p.usage & PROPERTY_USAGE_EDITOR or p.usage < PROPERTY_USAGE_EDITOR or p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			if !p.class_name:
				potential_properties.append(Property.new(p.name,p.type))
			#if p.class_name:
				#prints("cname",p.class_name)
			#prints("name",p.name)
			#if p.usage:
				#prints("usage",Quack.ByteUtils.to_binary_string(p.usage,false,29))
			#prints("hint",p.hint)
			#prints("hint string",p.hint_string)
			#prints("type", type_string(p.type))
			#print()
	for p in potential_properties:
		print(p)
	properties = potential_properties

## Checks only the [member source_script] if valid. Converts all script variables
## to [Property]s and appends them to [member properties].
@export_tool_button("check plist (script only)") var get_plist_short_func := func get_plist_short() -> void:
	if not source_script:
		printerr("Can't get a property list from a nonexistent script.")
		return
	var property_list := source_script.get_script_property_list()
	var potential_properties: Array[Property]
	for p in property_list:
		if p.usage & PROPERTY_USAGE_EDITOR or p.usage < PROPERTY_USAGE_EDITOR or p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			potential_properties.append(Property.new(p.name,p.type))
			#if p.class_name:
				#prints("cname",p.class_name)
			#prints("name",p.name)
			#if p.usage:
				#prints("usage",Quack.ByteUtils.to_binary_string(p.usage,false,29))
			#prints("hint",p.hint)
			#prints("hint string",p.hint_string)
			#prints("type", type_string(p.type))
			#print()
	for p in potential_properties:
		print(p)
	properties = potential_properties

func apply_to_array(node: Object, array: Array[Variant]) -> void:
	for i in num_props:
		array[i] = properties[i].get_property(node)

func get_array() -> Array[Variant]:
	var array: Array[Variant] = []
	array.resize(num_props)
	return array

func to_array(node: Object) -> Array[Variant]:
	var array := get_array()
	apply_to_array(node, array)
	return array

func from_array(array: Array[Variant], node: Object) -> void:
	for i in num_props:
		properties[i].set_property(array[i],node)

func from_array_no_nulls(array: Array[Variant], node: Object) -> void:
	var property: Variant
	for i in num_props:
		property = array[i]
		if property != null:
			properties[i].set_property(property,node)

func from_array_interpolated(array: Array[Variant], node: Object, weight: float) -> void:
	var property: Variant
	for i in num_props:
		property = array[i]
		if property != null:
			properties[i].set_property_interpolated(property,node,weight)

func encode_node(node: Object, buffer: StreamPeerBitBuffer) -> void:
	for property in properties:
		property.encode(property.get_property(node),buffer)

static func encode_owner_delta(buffer: StreamPeerBitBuffer) -> void:
	buffer.put_bool(node_changed)
	buffer.put_bool(node_delta)

static func encode_owner_spawn(uid: int, scene_id: int, buffer: StreamPeerBitBuffer) -> void:
	buffer.put_bool(node_changed)
	buffer.put_bool(node_not_delta)
	buffer.put_bool(node_spawned)
	buffer.put_u32(uid)
	buffer.put_u8(scene_id)

static func encode_owner_delete(uid: int, buffer: StreamPeerBitBuffer) -> void:
	buffer.put_bool(node_changed)
	buffer.put_bool(node_not_delta)
	buffer.put_bool(node_deleted)
	buffer.put_u32(uid)

func encode_array(array: Array[Variant], buffer: StreamPeerBitBuffer, vis_type: VisType = VisType.ALL) -> void:
	if not iters_visible[vis_type]: return
	encode_array_iter(array,buffer,iters[vis_type])

func encode_array_iter(array: Array[Variant], buffer: StreamPeerBitBuffer, iter: PackedByteArray) -> void:
	for i in iter:
		#Console.write("Encoding property %s [%s]"%[i,properties[i]])
		properties[i].encode(array[i],buffer)

func encode_delta_array(current: Array[Variant], prev: Array[Variant], buffer: StreamPeerBitBuffer, vis_type: VisType = VisType.ALL) -> void:
	assert(current.size() == prev.size(),"Sizes %s != %s"%[current.size(),prev.size()])
	assert(current.size() == num_props,"Sizes %s != %s"%[current.size(),num_props])
	
	if not iters_visible[vis_type]: return
	
	var this_node_changed := current != prev # FIXME slow
	buffer.put_bool(this_node_changed)
	if this_node_changed:
		encode_delta_array_iter(current,prev,buffer,iters[vis_type])

func encode_delta_array_iter(current: Array[Variant], prev: Array[Variant], buffer: StreamPeerBitBuffer, iter: PackedByteArray) -> void:
	var property: Property
	for i in iter:
		property = properties[i]
		if property.encode_type == Property.NetworkType.TYPE_BOOL:
			buffer.put_bool(current[i])
		else:
			if buffer.put_eval(current[i] != prev[i]):
				property.encode(current[i],buffer)

func decode(node: Object, buffer: StreamPeerBitBuffer) -> void:
	for property in properties:
		property.set_property(property.decode(buffer),node)

func decode_delta(node: Object, buffer: StreamPeerBitBuffer) -> void:
	for property in properties:
		if property.encode_type == Property.NetworkType.TYPE_BOOL:
			node[property.name] = buffer.get_bool()
		else:
			if buffer.get_bool():
				node[property.name] = property.decode(buffer)

func decode_array(array: Array[Variant], buffer: StreamPeerBitBuffer, vis_type: VisType) -> void:
	if not iters_visible[vis_type]: return
	decode_array_iter(array,buffer,iters[vis_type])

func decode_array_iter(array: Array[Variant], buffer: StreamPeerBitBuffer, iter: PackedByteArray) -> void:
	for i in iter:
		array[i] = properties[i].decode(buffer)
		#Console.write("Decoding property #%s (%s) [%s]"%[i,array[i],properties[i]])

func decode_delta_array(array: Array[Variant], buffer: StreamPeerBitBuffer, vis_type: VisType) -> void:
	if not iters_visible[vis_type]: return
	if not buffer.get_bool(): return
	decode_delta_array_iter(array,buffer,iters[vis_type])

func decode_delta_array_iter(array: Array[Variant], buffer: StreamPeerBitBuffer, iter: PackedByteArray) -> void:
	var property: Property
	for i in iter:
		property = properties[i]
		if property.encode_type == Property.NetworkType.TYPE_BOOL:
			array[i] = buffer.get_bool()
		else:
			if buffer.get_bool():
				array[i] = property.decode(buffer)
