extends CollisionShape3D

const ColliderComponent = preload("res://gameplay/player/collider_component.gd")

static var component_list: Dictionary[CollisionObject3D,ColliderComponent]

@onready var object: CollisionObject3D = get_parent() as CollisionObject3D

func _ready() -> void:
	component_list[object] = self
	if Quack.can_add_debug_mesh() and (ProjectSettings.get_setting_safe("quack/debug/show_owned_player_collisions",false) or object != Quack.tree.get_first_node_in_group(&"Player")):
		Quack.spawn_debug_mesh_child(self)

func _exit_tree() -> void:
	component_list.erase(object)
