extends StaticBody3D

const NetworkBoundingBoxComponent = preload("res://gameplay/network_bounding_box_component.gd")
const Collision = preload("res://gameplay/collision.gd")
const ColliderComponent = preload("res://gameplay/player/collider_component.gd")
const HitResolver = preload("res://gameplay/level/common/multiplayer_level.gd").HitResolver

@export var mesh: MeshInstance3D
static var component_list: Dictionary[MeshInstance3D,NetworkBoundingBoxComponent]

var states: Array[AABB]
var state_idx: int = -1
# NOTE this should eventually be something like the tickrate or a factor of the
# tickrate, but for now just keep it at 256 for parity with history saver
# recent frames count.
var num_states: int = 256#Quack.Tickrate.target_physics_rate

var collider: CollisionShape3D = CollisionShape3D.new()
var shape: BoxShape3D = BoxShape3D.new()
func _init() -> void:
	if not Quack.Network.is_server():
		queue_free()
	add_child(collider)
	collider.shape = shape
	states.resize(num_states)

func _ready() -> void:
	component_list[mesh] = self
	process_mode = Node.PROCESS_MODE_PAUSABLE
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fill_states.call_deferred()

func fill_states() -> void:
	var aabb := mesh.get_aabb()
	aabb.position += mesh.global_position
	states.fill(aabb)

func _exit_tree() -> void:
	component_list.erase(mesh)

func tick_state(aabb: AABB) -> void:
	state_idx = wrapi(state_idx+1,0,num_states)
	states[state_idx] = aabb

func _physics_process(_delta: float) -> void:
	var aabb := mesh.get_aabb()
	aabb.position += mesh.global_position
	tick_state(aabb)
	for state in states:
		aabb = aabb.merge(state)
		#for i in aabb.position:
			#if i < largest_aabb.position[i]:
				#largest_aabb.position[i] = aabb.position[i]
		#for i in aabb.end:
			#pass
	global_position = aabb.get_center()
	shape.size = aabb.size

static func can_show_hitreg() -> bool:
	return ProjectSettings.get_setting_safe("quack/debug/show_hitreg",false) as bool

static func get_raycast_intersections(raycast: RayCast3D, disable_after: bool = false) -> Array[NetworkBoundingBoxComponent]:
	var mask := raycast.collision_mask
	raycast.collision_mask = Collision.Layer.NETWORK# | Collision.Layer.WORLD this would be a good optimization but if penetration is enabled or the ray is supposed to go thru world geo then this is a bad idea
	var collisions: Array[NetworkBoundingBoxComponent]
	var last_collision: Object
	
	raycast.enabled = true
	raycast.force_raycast_update()
	var show_hitreg := can_show_hitreg()
	if show_hitreg:
		Quack.spawn_debug_raycast_mesh(raycast,10.)
	while raycast.is_colliding():
		last_collision = raycast.get_collider()
		if last_collision is NetworkBoundingBoxComponent:
			# Cuz i dont want to type lmao
			var casted := last_collision as NetworkBoundingBoxComponent
			collisions.append(casted)
			raycast.add_exception(casted)
			if show_hitreg:
				add_debug_mesh(casted)
		else:
			Console.writerr("%s is not a bounding box."%last_collision)
			break
		raycast.force_raycast_update()
	for collision in collisions:
		raycast.remove_exception(collision)
	
	raycast.collision_mask = mask
	if disable_after:
		raycast.enabled = false
	
	return collisions

static func get_ray_intersection_intersections(world: World3D, ray_intersection: PhysicsRayQueryParameters3D) -> Array[NetworkBoundingBoxComponent]:
	var mask := ray_intersection.collision_mask
	ray_intersection.collision_mask = Collision.Layer.NETWORK# | Collision.Layer.WORLD this would be a good optimization but if penetration is enabled or the ray is supposed to go thru world geo then this is a bad idea
	var collisions: Array[NetworkBoundingBoxComponent]
	var last_collision: Object
	
	var show_hitreg := can_show_hitreg()
	if show_hitreg:
		Quack.draw_line(ray_intersection.from,ray_intersection.to,10.)
	var result := world.direct_space_state.intersect_ray(ray_intersection)
	while result:
		last_collision = result.collider
		if last_collision is NetworkBoundingBoxComponent:
			# Cuz i dont want to type lmao
			var casted := last_collision as NetworkBoundingBoxComponent
			collisions.append(casted)
			var exclude := ray_intersection.exclude
			exclude.append(casted.get_rid())
			ray_intersection.exclude = exclude
			if show_hitreg:
				add_debug_mesh(casted)
		else:
			Console.writerr("%s is not a bounding box."%last_collision)
			break
		result = world.direct_space_state.intersect_ray(ray_intersection)
	for collision in collisions:
		var exclude := ray_intersection.exclude
		exclude.erase(collision)
		ray_intersection.exclude = exclude
	
	ray_intersection.collision_mask = mask
	
	return collisions

static var bb_frames: Dictionary[NetworkBoundingBoxComponent,Dictionary]
static var bb_meshes: Dictionary[int,MeshInstance3D]
static var meshes: Dictionary[MeshInstance3D,NetworkBoundingBoxComponent]
static func add_debug_mesh(box: NetworkBoundingBoxComponent) -> void:
	var frame := Engine.get_physics_frames()
	if bb_frames.has(box):
		var dict := bb_frames[box]
		if dict.has(frame):
			return
		else:
			var mesh := Quack.spawn_recolored_colldier_debug_mesh(box.collider,Color.ORANGE - Color(0,0,0,.9),10.)
			mesh.tree_exiting.connect(on_debug_mesh_removed.bind(mesh,frame))
			dict[frame] = mesh
			meshes[mesh] = box
	else:
		var mesh := Quack.spawn_recolored_colldier_debug_mesh(box.collider,Color.ORANGE - Color(0,0,0,.9),10.)
		mesh.tree_exiting.connect(on_debug_mesh_removed.bind(mesh,frame))
		bb_frames[box] = {frame: mesh}
		meshes[mesh] = box

static func on_debug_mesh_removed(mesh: MeshInstance3D, frame: int) -> void:
	var box := meshes[mesh]
	meshes.erase(box)
	var dict := bb_frames[box]
	dict.erase(frame)
	if dict.is_empty():
		bb_frames.erase(box)

static func get_shapecast_intersections(shapecast: ShapeCast3D, disable_after: bool = false) -> Array[NetworkBoundingBoxComponent]:
	var mask := shapecast.collision_mask
	shapecast.collision_mask = Collision.Layer.NETWORK
	var collisions: Array[NetworkBoundingBoxComponent]
	var last_collision: Object
	
	var show_hitreg := can_show_hitreg()
	if show_hitreg:
		Quack.spawn_recolored_debug_mesh(shapecast.shape.get_debug_mesh(),Color(1,0,0,.1),shapecast.global_transform,10.)
	shapecast.enabled = true
	shapecast.force_shapecast_update()
	while shapecast.is_colliding():
		for i in shapecast.get_collision_count():
			last_collision = shapecast.get_collider(i)
			if last_collision is NetworkBoundingBoxComponent:
				# Cuz i dont want to type lmao
				var casted := last_collision as NetworkBoundingBoxComponent
				collisions.append(casted)
				shapecast.add_exception(casted)
				if show_hitreg:
					add_debug_mesh(casted)
			else:
				Console.writerr("%s is not a bounding box"%last_collision)
			shapecast.force_shapecast_update()
	for collision in collisions:
		shapecast.remove_exception(collision)
	
	shapecast.collision_mask = mask
	if disable_after:
		shapecast.enabled = false
	
	return collisions

static func get_characterbody_intersections(characterbody: CharacterBody3D, move_delta: float) -> Array[NetworkBoundingBoxComponent]:
	var collider := ColliderComponent.component_list.get(characterbody) as ColliderComponent
	if not collider:
		return []
	
	var shapecast := ShapeCast3D.new()
	var shape := BoxShape3D.new()
	var frame_vel := characterbody.get_real_velocity() * move_delta
	shape.size = Collision.get_shape_extents(collider.shape)
	
	shapecast.shape = shape
	characterbody.add_child(shapecast)
	shapecast.position = frame_vel / 2.
	
	var collisions := get_shapecast_intersections(shapecast)
	
	shapecast.queue_free()
	
	return collisions

static func get_area_intersections(area: Area3D) -> Array[NetworkBoundingBoxComponent]:
	var collider := ColliderComponent.component_list.get(area) as ColliderComponent
	if not collider:
		return []
	
	var shapecast := ShapeCast3D.new()
	shapecast.shape = collider.shape
	area.add_child(shapecast)
	
	var collisions := get_shapecast_intersections(shapecast)
	
	shapecast.queue_free()
	
	return collisions

# Fuck you!
#static func get_rigidbody_intersections(rigidbody: RigidBody3D, move_delta: float) -> Array[NetworkBoundingBoxComponent]:
	#var collider := ColliderComponent.component_list.get(characterbody) as ColliderComponent
	#if not collider:
		#return []
	#var shapecast
