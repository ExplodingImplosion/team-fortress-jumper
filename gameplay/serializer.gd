extends Node

const QuackMultiplayer = preload("res://network/multiplayer/quack_multiplayer.gd")
const Network = preload("res://network/network.gd")
const Serializer = preload("res://gameplay/serializer.gd")
const StreamPeerBitBuffer = preload("res://utils/stream_peer_bit_buffer.gd")
const PhysicsPriority = preload("res://utils/process_priorities.gd").Physics.Priorities
const OwnerID = preload("res://gameplay/owner_id.gd")
const Team = preload("res://gameplay/team_component.gd")

## Array of [NetworkedNode]s to match [member nodes] (unless in the future
## [member test_dict] winds up being used), that describes the serialization
## profile for each node in the scene that will be networked.
@export var serialization_properties: Array[NetworkedNode]
## Array of [Node]s to match [member serialization_properties] (unless in the
## future [member test_dict] winds up being used), that describes the nodes that
## will be networked with their corresponding serialization profile.
@export var nodes: Array[Node]
## Might be used to replace [member serialization_properties] and [member nodes]
## in the future.
@export var test_dict: Dictionary[Node,NetworkedNode]
## The minimum frequency with which [member nodes] will be serialized. If less
## than the network framerate, this property will have no effect.
@export var update_frequency: float
var update_time_left: float
var updating: bool = false
var uid: int = 0
var scene_id: int = 0
var predicted: bool = false

# This was added because when you shoot a rocket, it moves forward one frame.
# (see projectile.gd apply_speed() function for reference). If you're right up
# against a wall, something like a rocket spawns an explosion from within that
# same funciton / time frame, which is in call_deferred time on that same frame
# because apply_speed is connected to the projectile's ready function, with a
# deferred flag. This means that its serializer doesn't serialize initially in time
# for a history_saver serialization to use it, and it errors out because it's trying
# to serialize a bunch of nulls. So this is here as a band-aid to make sure that
# everything's been serialized properly lmfao
var has_serialized: bool = false
var serialized: SerializedNodeCollection

signal updated

static var component_list: Dictionary[Node,Serializer]
static var component_tracker := ComponentTracker.new()
static var uid_map: Dictionary[int,Serializer]
static var uid_index: int = 0

static func get_uid_by_node(node: Node) -> int:
	if node == null: return -1;
	if component_list.has(node.owner):
		return component_list[node.owner].uid
	else:
		if component_list.has(node):
			return component_list[node].uid
		else:
			return -1

static func get_serializers() -> Array[Serializer]:
	return Array(component_list.values(),TYPE_OBJECT,&"Node",Serializer) as Array[Serializer]

func increment_uid() -> void:
	uid = uid_index
	uid_map[uid_index] = self
	scene_id = QuackMultiplayer.scene_registry[owner.scene_file_path]
	uid_index += 1

func clear_uid() -> void:
	uid_map.erase(uid)

class ComponentTracker:
	signal component_added(component: Serializer)
	signal component_removed(component: Serializer)

func get_update_weight() -> float:
	if update_frequency == 0.:
		return 1.
	return update_time_left / update_frequency

func _physics_process(delta: float) -> void:
	if Network.is_server():
		if Network.is_in_multiplayer():
			updating = false
			update_time_left += delta
			if update_time_left >= update_frequency:
				serialize_nodes.call_deferred()
				updating = true
				update_time_left = 0.
	else:
		if updating:
			if update_frequency == 0.:
				receive_update(serialized.property_lists)
			else:
				update_time_left += delta
				receive_update_interpolated(serialized.property_lists)
				if update_time_left >= update_frequency:
					updating = false
					update_time_left = 0.

func serialize_nodes() -> void:
	for i in nodes.size():
		serialization_properties[i].apply_to_array(nodes[i],serialized.property_lists[i])
	has_serialized = true

func should_serialize() -> bool:
	return Network.is_server() and Network.is_in_multiplayer()

func _enter_tree() -> void:
	component_list[owner] = self
	# maybe turn this to tree_exiting? NOTE: this is untested but seems to be
	# due to it being specifically looking at the OWNER, and not, say, the
	# serializer's PARENT. Because other components clean up after themselves
	# just fine. Weird, but if true, is good reason to leave this like this.
	# Because explaining to someone that for this one specific node you have to
	# connect EXCLUSIVELY ITS TREE EXITING FUNCTION when everything else is done
	# for you is goofy. Also, maybe it should just be manually connected in each
	# scene that it's in? But that still messes with the pattern...
	owner.tree_exited.connect(on_owner_exit_tree.bind(owner))
	if should_serialize():
		serialize_nodes.call_deferred()
		# This 0 might not work
		#update.call_deferred(0,serialized)
	component_tracker.component_added.emit(self)

func on_owner_exit_tree(node_owner: Node) -> void:
	component_list.erase(node_owner)
	component_tracker.component_removed.emit(self)
	clear_uid()

func _ready() -> void:
#region Assertions
	assert(serialization_properties.size() == nodes.size(),
	"Serialization properties size %s must match nodes size %s!"%
	[serialization_properties.size(),nodes.size()])
	assert(nodes_are_valid(),"Nodes are invalid somehow. At least one node is null or an invalid instance.")
	# Don't serialize anything because there's nothing to serialize lmao
	if nodes.is_empty():
		return
	assert(owner == nodes[0],
"The first node in nodes must be the scene owner, but scene owner %s [%s], and first node is %s [%s]."%
[owner.name,owner,nodes[0].name,nodes[0]])
#endregion
	var property_lists: Array[Array] = []
	var num_nodes: int = serialization_properties.size()
	property_lists.resize(num_nodes)
	for i in num_nodes:
		property_lists[i] = serialization_properties[i].get_array()
	serialized = SerializedNodeCollection.new(property_lists,uid,scene_id,OwnerID.get_node_owner_id(owner),Team.get_node_team_id(owner),Network.MultiplayerSession.frame_num,serialization_properties)
	process_physics_priority = PhysicsPriority.SERIALIZER
	# Maybe (update: yes)
	process_mode = Node.PROCESS_MODE_PAUSABLE

func nodes_are_valid() -> bool:
	var i: int = 0
	for node in nodes:
		if node == null:
			Console.push_err("Node at index %s is null."%i)
			return false
		elif !is_instance_valid(node):
			Console.push_err("Node %s at index %s is null."%[node,i])
			return false
		i += 1
	return true

func update_physical_properties(properties: Array[Array], weight: float = 1., notify_transform_changed: bool = true) -> void:
	#Console.write("Updating physical properties on %s at %s"%[owner.name,weight])
	for i in nodes.size():
		var config := serialization_properties[i]
		var property: Property
		var array := properties[i]
		var value: Variant
		for prop_idx in serialization_properties[i].iter_physical:
			property = config.properties[prop_idx]
			# If you dont remember writing this, its safe to delete. was just
			# a sanity check the first time this was implemented
			assert(property.physical)
			#if property.physical:
			value = array[prop_idx]
			if value != null:
				#Console.write("Changing property %s from %s to %s"%[
					#property.name,property.get_property(nodes[i]),value
				#])
				property.set_property_interpolated(value,nodes[i],weight)
	if notify_transform_changed and owner is Node3D:
		# Why does this work but force_update_transform doesnt lmfao
		owner.propagate_notification(Node3D.NOTIFICATION_TRANSFORM_CHANGED)
		#(owner as Node3D).force_update_transform()

func receive_update(properties: Array[Array]) -> void:
	for i in nodes.size():
		serialization_properties[i].from_array_no_nulls(properties[i],nodes[i])
	updated.emit()

func receive_update_interpolated(properties: Array[Array]) -> void:
	for i in nodes.size():
		serialization_properties[i].from_array_interpolated(properties[i],nodes[i],get_update_weight())
	updated.emit()

func receive_instant_update(properties: Array[Array]) -> void:
	for i in nodes.size():
		serialization_properties[i].from_array_no_nulls(properties[i],nodes[i])
	owner.reset_physics_interpolation()
	updated.emit()

#func encode_nodes(buffer: StreamPeerBitBuffer) -> void:
	#for i in nodes.size():
		#serialization_properties[i].encode_node(nodes[i],buffer)

#func encode(buffer: StreamPeerBitBuffer) -> void:
	#for i in nodes.size():
		#serialization_properties[i].encode_array(serialized[i],buffer,)

func decode_nodes(buffer: StreamPeerBitBuffer) -> void:
	for i in nodes.size():
		serialization_properties[i].decode(nodes[i],buffer)

func delta_decode_nodes(buffer: StreamPeerBitBuffer) -> void:
	var s_props: NetworkedNode
	for i in nodes.size():
		s_props = serialization_properties[i]
		if buffer.get_bool():# == NetworkedNode.node_changed:
			s_props.decode_delta(nodes[i],buffer)

func decode(buffer: StreamPeerBitBuffer, vis_type: Property.VisibilityType = Property.VisibilityType.ALL) -> void:
	serialized.decode_spawn(buffer,vis_type)
	receive_instant_update.call_deferred(serialized.property_lists)

func decode_delta(buffer: StreamPeerBitBuffer, vis_type: Property.VisibilityType) -> void:
	serialized.decode_delta(buffer,vis_type)
	updating = true
	update_time_left = 0.

class SerializedNodeCollection:
	var node_configs: Array[NetworkedNode]
	var property_lists: Array[Array]
	var num_nodes: int
	var uid: int
	var scene_id: int
	var owner_id: int
	var team: int
	var frame_created: int
	var frame_deleted: int = -1
	#var flags: NetworkedNode.StatusFlags
	
	func spawn(scene: Node) -> Node:
		Serializer.uid_index = uid
		var node := QuackMultiplayer.scenes[scene_id].instantiate()
		scene.add_child(node)
		var serializer := Serializer.component_list[node]
		serializer.receive_instant_update.call_deferred(property_lists)
		return node
	
	func was_deleted() -> bool:
		return frame_deleted > -1
	
	func _to_string() -> String:
		return "SerializedNodeCollection (UID %s, owner %s, team %s, %s serialized nodes, scene %s [%s])"%[
			uid,owner_id,team,num_nodes,scene_id,QuackMultiplayer.scenes[scene_id].resource_path.get_file()
		]
	
	func duplicate() -> SerializedNodeCollection:
		return SerializedNodeCollection.new(property_lists,uid,scene_id,owner_id,team,frame_created,node_configs,true)
	
	static func create_fresh(uid: int, scene_id: int, owner_id: int, team: int, frame_created: int, node_configs: Array[NetworkedNode]) -> SerializedNodeCollection:
		var property_lists: Array[Array] = []
		var num_nodes: int = node_configs.size()
		property_lists.resize(num_nodes)
		for i in num_nodes:
			property_lists[i] = node_configs[i].get_array()
		return SerializedNodeCollection.new(property_lists,uid,scene_id,owner_id,team,frame_created,node_configs,false)
	
	func _init(property_lists: Array[Array], uid: int, scene_id: int, owner_id: int, team: int, frame_created: int, node_configs: Array[NetworkedNode], duplicate: bool = true) -> void:
		self.uid = uid
		self.scene_id = scene_id
		self.property_lists = property_lists.duplicate(true) as Array[Array] if duplicate else property_lists
		#nodes_properties = serializer.serialized.duplicate(true) as Array[Array] if duplicate else serializer.serialized
		self.node_configs = node_configs
		num_nodes = node_configs.size()
		self.owner_id = owner_id
		self.team = team
		self.frame_created = frame_created
	
	func encode_spawn(buffer: StreamPeerBitBuffer, vis_type: Property.VisibilityType = Property.VisibilityType.OWNER_ONLY) -> void:
		for i in num_nodes:
			node_configs[i].encode_array(property_lists[i], buffer, vis_type)
	
	func decode_spawn(buffer: StreamPeerBitBuffer, vis_type: Property.VisibilityType = Property.VisibilityType.OWNER_ONLY) -> void:
		for i in num_nodes:
			node_configs[i].decode_array(property_lists[i], buffer, vis_type)
	
	func encode_delta(prev: SerializedNodeCollection, buffer: StreamPeerBitBuffer, vis_type: Property.VisibilityType) -> void:
		for i in num_nodes:
			node_configs[i].encode_delta_array(property_lists[i],prev.property_lists[i],buffer,vis_type)
	
	func decode_delta(buffer: StreamPeerBitBuffer, vis_type: Property.VisibilityType) -> void:
		for i in num_nodes:
			node_configs[i].decode_delta_array(property_lists[i],buffer,vis_type)

static func get_serialization_info(scene: PackedScene, scene_id: int, state := scene.get_state()) -> SerializedNodeCollection:
	for node_idx in state.get_node_count():
		var is_serializer: bool = false
		var node_configs: Array[NetworkedNode]
		for prop_idx in state.get_node_property_count(node_idx):
			var property: Variant = state.get_node_property_value(node_idx,prop_idx)
			if (property is GDScript) and (property as GDScript) == Serializer:
				Console.writeverb.call_deferred(" ".join([scene.resource_path,state.get_node_name(node_idx),state.get_node_property_name(node_idx,prop_idx),"is Serializer!"]))
				is_serializer = true
			#elif property is Array[NetworkedNode]
			elif property is Array[NetworkedNode]:
				assert(state.get_node_property_name(node_idx,prop_idx) == "serialization_properties","Why is %s not serialization_properties"%state.get_node_property_name(node_idx,prop_idx))
				assert(node_configs.is_empty())
				node_configs = property
		if is_serializer:
			return SerializedNodeCollection.create_fresh(-1,scene_id,-1,-1,-1,node_configs)
	var base := state.get_base_scene_state()
	if base:
		return get_serialization_info(scene,scene_id,base)
	return null
