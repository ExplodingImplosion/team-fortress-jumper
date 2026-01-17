extends StaticBody3D

const ColliderComponent = preload("res://gameplay/player/collider_component.gd")
const Collision = preload("res://gameplay/collision.gd")
const Hitbox = preload("res://gameplay/hitbox.gd")

#static var hitboxes: Dictionary[Hitbox,Node]
static var hitbox_owners: Dictionary[Node,Array]

func _ready() -> void:
	collision_layer |= Collision.Layer.HITBOX
	collision_mask = 0
	#Hitbox.hitboxes[self] = owner
	if Hitbox.hitbox_owners.has(owner):
		Hitbox.hitbox_owners[owner].append(self)
	else:
		var array: Array[Hitbox] = [self]
		Hitbox.hitbox_owners[owner] = array
	owner.tree_exited.connect(on_owner_exit_tree.bind(owner))

# NOTE This is done this way because of weirdness. Check out comment on line ~110
# in serializer.gd.
func on_owner_exit_tree(node_owner: Node) -> void:
	#hitboxes.erase(self)
	var array: Array[Hitbox] = Hitbox.hitbox_owners[node_owner]
	if array.size() == 1:
		#array.clear() # idk if this happens by default
		Hitbox.hitbox_owners.erase(node_owner)
	

static func get_parent_collider_component(collider: CollisionObject3D) -> ColliderComponent:
	if collider.collision_layer & Collision.Layer.HITBOX:#collider is Hitbox:
		return ColliderComponent.component_list.get(
			(collider as Hitbox).owner as CollisionObject3D
		)
	else:
		return ColliderComponent.component_list.get(collider)
