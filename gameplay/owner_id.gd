extends Node

const OwnerID = preload("res://gameplay/owner_id.gd")
const Serializer = preload("res://gameplay/serializer.gd")

@export var owner_id: int
var group_name: StringName

static var component_list: Dictionary[Node,OwnerID]
signal owner_changed

@onready var parent: Node = get_parent()

func get_group_name() -> StringName:
	return StringName(str(owner_id))

func assign_group() -> void:
	group_name = get_group_name()
	parent.add_to_group(group_name)
	parent.set_multiplayer_authority(owner_id)

func reassign_group() -> void:
	if group_name != get_group_name():
		remove_from_group(group_name)
		assign_group()
		owner_changed.emit()

func _ready() -> void:
	component_list[parent] = self
	assign_group()
	# NOTE i was gonna have this in its own deferred function but because
	# serializers are unique in that they add themselves to their component
	# specifically in their _enter_tree function. if this stuff is moved to
	# _enter_tree, then this stuff is gonna need to be deferred, or some other
	# solution will need to be found
	if Serializer.component_list.has(parent):
		Serializer.component_list[parent].updated.connect(reassign_group)

func _exit_tree() -> void:
	component_list.erase(parent)

# TODO: At some point, it would probably be a good idea
func propagate_to(node: Node) -> void:
	add_node_owner(node,owner_id)

static func add_node_owner(node: Node, id: int) -> void:
	# If a node's owner ID already exists, just propagate the owner ID
	var existing := OwnerID.get_node_owner(node)
	if existing != null:
		existing.parent.remove_from_group(existing.group_name)
		existing.owner_id = id
		existing.reassign_group()
		return
	# Otherwise, create a new owner ID node
	var new := OwnerID.new()
	new.owner_id = id
	node.add_child(new)

static func get_node_owner(node: Node) -> OwnerID:
	# Functionally identical to
	# return component_list[node] if component_list.has(node) else null
	return component_list.get(node)

static func has(node: Node) -> bool:
	return component_list.has(node)

static func node_is_owned_by(node: Node, id: int) -> bool:
	var node_owner := get_node_owner(node)
	return node_owner and node_owner.owner_id == id

# Might be faster than is_owned_by idk
static func node_is_in_owner_group(node: Node, id: int) -> bool:
	return node.is_in_group(StringName(str(id)))

static func nodes_share_owner(node1: Node, node2: Node) -> bool:
	return node_is_owned_by(node2,component_list[node1].owner_id) if has(node1) else false

static func get_nodes_owned_by(id: int) -> Array[Node]:
	return Quack.tree.get_nodes_in_group(StringName(str(id)))

static func get_node_owner_id(node: Node) -> int:
	var node_owner := get_node_owner(node)
	if node_owner:
		return node_owner.owner_id
	else:
		return 0

const Sesh = Serializer.Network.MultiplayerSession
const Client = Sesh.Client
static func get_node_client_owner(node: Node) -> Client:
	var id := get_node_owner_id(node)
	if id:
		# lmao
		var players := Sesh.players
		if players.has(id):
			return players[id].client
	
	return null

const QuackPlayer = Sesh.QuackPlayer
static func get_node_player_owner(node: Node) -> QuackPlayer:
	var id := get_node_owner_id(node)
	if id:
		var players := Sesh.players
		if players.has(id):
			return players[id]
	
	return null

func get_player_owner() -> QuackPlayer:
	var players := Sesh.players
	if players.has(owner_id):
		return players[owner_id]
	return null
