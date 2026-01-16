extends Node

const TeamComponent = preload("res://gameplay/team_component.gd")

@export_custom(PROPERTY_HINT_FLAGS,"
Always Hostile,
Team 1,
Team 2,
"
) var team_id: int = FLAG_ALWAYS_HOSTILE
var group_name: StringName
const FLAG_ALWAYS_HOSTILE = 1

static var component_list: Dictionary[Node,TeamComponent]

static func get_nodes_with_teams() -> Array[Node]:
	return Array(component_list.keys(),TYPE_OBJECT,&"Node",null) as Array[Node]

@onready var parent: Node = get_parent()

func get_group_name() -> StringName:
	return StringName("Team%s"%team_id)

func assign_group() -> void:
	group_name = get_group_name()
	parent.add_to_group(group_name)

func reassign_group() -> void:
	remove_from_group(group_name)
	assign_group()

func _ready() -> void:
	component_list[parent] = self
	assign_group()

func _exit_tree() -> void:
	component_list.erase(parent)

# TODO: At some point, it would probably be a good idea
func propagate_to(node: Node) -> void:
	add_node_team(node,team_id)

static func add_node_team(node: Node, team: int) -> void:
	# If a node's owner ID already exists, just propagate the owner ID
	var existing := TeamComponent.get_node_team_component(node)
	if existing != null:
		existing.parent.remove_from_group(existing.group_name)
		existing.team_id = team
		existing.reassign_group()
		return
	# Otherwise, create a new owner ID node
	var new := TeamComponent.new()
	new.team_id = team
	node.add_child(new)

static func get_node_team_component(node: Node) -> TeamComponent:
	# Functionally identical to
	# return component_list[node] if component_list.has(node) else null
	return component_list.get(node)

static func try_propagate_to(from: Node, to: Node) -> void:
	var team := get_node_team_component(from)
	if team != null:
		team.propagate_to(to)

static func has(node: Node) -> bool:
	return component_list.has(node)

static func node_is_on_team(node: Node, team: int) -> bool:
	if team & FLAG_ALWAYS_HOSTILE:
		return false
	var component := get_node_team_component(node)
	return component and component.team_id & team

# Might be faster than is_on_team idk
static func node_is_in_team_group(node: Node, team: int) -> bool:
	return node.is_in_group("Team%s"%team)

static func get_nodes_on_team(team: int) -> Array[Node]:
	return Quack.tree.get_nodes_in_group("Team%s"%team)

static func nodes_are_on_same_team(node1: Node, node2: Node) -> bool:
	return node_is_on_team(node2,component_list[node1].team_id) if has(node1) else false

static func all_nodes_are_on_same_team(array: Array[Node]) -> bool:
	if array.is_empty():
		return false
	var node1: Node = array[0]
	if Quack.is_node_valid(node1):
		for i in array.size()-1:
			if not nodes_are_on_same_team(node1,array[i+1]):
				return false
	return true

static func teams_are_friendly(team1: int, team2: int) -> bool:
	return ( not (team1 & FLAG_ALWAYS_HOSTILE or team2 & FLAG_ALWAYS_HOSTILE) ) and (team1 & team2)

static func get_node_team_id(node: Node) -> int:
	return 0 if not component_list.has(node) else component_list[node].team_id
