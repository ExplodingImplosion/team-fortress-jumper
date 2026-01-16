extends Node

#region script consts
const TimeUtils = preload("res://utils/time_utils.gd")
const Tickrate = preload("res://utils/tickrate.gd")
const WindowUtils = preload("res://utils/window_utils.gd")
const ConnectivityTester = preload("res://network/connectivity_tester.gd")
const Network = preload("res://network/network.gd")
const ByteUtils = preload("res://utils/byte_utils.gd") # not directly used in this script, but other scripts have a dependency on it lmao hehe
const Audio = preload("res://utils/audio.gd")
const GraphicsSettings = preload("res://utils/graphics_settings.gd")
const ThreadUtils = preload("res://utils/thread_utils.gd")
const Replays = preload("res://network/multiplayer/replays.gd")
const Splitscreen = preload("res://interface/splitscreen/splitscreen.gd")
const ProcessPriorities = preload("res://utils/process_priorities.gd")
#endregion

## Setting path to access the number of desired users playing the game.
const NUM_USERS_SETTING = "quack/gameplay/number_of_players"

## Dictionary of [Node]s that are currently removed from [member tree], but are not freed from
## memory. Keys are the nodes' instance ID's. Values are references to the nodes
## themselves.
var removed_nodes: Dictionary = {}
## Dictionary of [int]'s serving as node ID's for each [Node] in [member removed_nodes].
## Keys are [Nodes]s in [member removed_nodes] (calling [method Dictionary.values]
## is the same as calling [method Dictionary.keys] on [member removed_node_ids])
## Values are the nodes' multiplayer ID's.
var removed_node_ids: Dictionary = {}
## The number of desired users playing the game.
var num_users: int = 1

## The player's username. Hopefully will be depreciated soon.
var username: String

## Cached accessor for the game's root [Window]. Accessing this is functionally
## the same as [method get_root]. Updated by default before [method _ready] is
## called.
@onready var root: Window = get_root()
##Cached accessor for the game's [SceneTree]. Accessing this is functionally the
## same as [method Node.get_tree]. Updated by default before [method _ready] is called.
@onready var tree: SceneTree = get_tree()
## Cached accessor for the game's [PhysicsDirectSpaceState3D]. Accessing this
## is functionally the same as accessing [member root]'s [code]world_3d[/code]'s
## [code]direct_space_state[/code]. Declared before [method _ready] is called,
## but assigned at the end of the first time [method _physics_process] is called.
@onready var query: PhysicsDirectSpaceState3D# = root.world_3d.direct_space_state

@warning_ignore("unused_parameter")
func _physics_process(delta: float) -> void:
	# Maybe instead connect this to tree.process_frame to get earliest possible call
	TimeUtils.update_physics_times()
	if TimeUtils.is_startup() and query == null:
		query = root.world_3d.direct_space_state

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	# Maybe instead connect this to tree.process_frame to get earliest possible call
	TimeUtils.update_process_times()
#	if current_time_thread != current_time:
#		print("main: threaded time %s != %s"%[current_time_thread, current_time])

func _init() -> void:
	ProcessPriorities.set_singleton(self)
#	stupid_shader_cache_workaround()
	# Passing self cuz 'Quack' as a thing isnt initialized yet is is insanely stupid
	#assert(!Resources.resources.is_empty())
	Tickrate.initialize()
	num_users = ProjectSettings.get_setting(NUM_USERS_SETTING,1)
	assert_valid_number_of_users()
	# maybe put this at the end of _ready()?
	TimeUtils.begin_physics_tracking()
	ProjectSettings.set_setting(BOOT_SPLASH_SETTING_PATH,boot_splashes[wrapi(boot_splashes.find(ProjectSettings.get_setting(BOOT_SPLASH_SETTING_PATH,"res://interface/splashes/no_grass.png"))+1,0,boot_splashes.size())] if !is_exported() else "res://interface/splashes/no_grass.png")

const BOOT_SPLASH_SETTING_PATH = "application/boot_splash/image"
const boot_splashes: PackedStringArray = [
	"res://interface/splashes/exclamation_marks.png",
	"res://interface/splashes/no_grass.png",
	"res://interface/splashes/outline.png",
	"res://interface/splashes/water.png",
	"res://garbage.png"
	]

func stupid_shader_cache_workaround() -> void:
	var node := Node.new()
	add_child(node)
	Console.push_warn("Resources script isn't a thing")
	# HACK lmao
	for resource in []:
		if resource is PackedScene:
			node.add_child(resource.instantiate())
		elif resource is Material:
			var mesh := MeshInstance3D.new()
			mesh.set_mesh(BoxMesh.new())
			mesh.mesh.surface_set_material(0,resource)
			node.add_child(mesh)
	for child in node.get_children():
		child.queue_free()
	node.queue_free()

func get_debug_transparent_material() -> StandardMaterial3D:
	return null #Resources.get_resource(Resources.DEBUGTRANSPARENTMATERIAL)

func _ready() -> void:
	setup_connections()
	setup_filepaths()
	WindowUtils.initialize_general_settings()
	# move this to audio script if there's more settings that get updated
	AudioServer.set_bus_volume_linear(Audio.get_master_volume_bus_idx(),Audio.get_volume())
	if Network.get_online():
		ConnectivityTester.test_internet_connection()
	else:
		Console.write_in_color("Starting in offline mode.",Color.DARK_ORANGE)
	on_scene_changed.call_deferred()
	multiplayer.set_server_relay_enabled(false)
	ThreadUtils.add_thread(Network.initialize)
	# might be able to get rid of this tbh, this is legacy and untested as
	# to whether getting rid of it causes any issues
	Tickrate.auto_assign_physics_delta.call_deferred()

const USER_DIRECTORY: String = "user://"
const SETTING_FILEPATH: String = "override.cfg"
var legaming_patch_app_hack := OS.get_executable_path().get_base_dir()+"/"+SETTING_FILEPATH if is_exported() else "res://"+SETTING_FILEPATH
func _exit_tree() -> void:
	ProjectSettings.save_custom(legaming_patch_app_hack)

func setup_filepaths() -> void:
	@warning_ignore("static_called_on_instance")
	setup_directory(USER_DIRECTORY)
	# same as setup_directory(Replays.REPLAY_DIRECTORY)
	Replays.setup_filepath()

static func setup_directory(directory: String) -> void:
	if !DirAccess.dir_exists_absolute(directory):
		# maybe make_dir_recursive?
		var err := DirAccess.make_dir_absolute(directory)
		if err != OK:
			Console.writerr("Failed to create directory at %s. Got error %s."%[directory,error_string(err)])

func setup_connections() -> void:
	root.size_changed.connect(on_window_resized)
	root.focus_entered.connect(on_window_focused)
	root.focus_exited.connect(on_window_unfocused)
	# dumb hack, cuz godot treats going to console as losing focus for main window
	setup_window_focus(Console)

enum {DEFAULT_WINDOW_SIZE_x = 1152,DEFAULT_WINDOW_SIZE_y = 648}
func on_window_resized() -> void:
	for node in get_nodes_in_group(&"Basic Scaling"):
		if node is Control:
			node.set_scale(Vector2(root.size.x/float(DEFAULT_WINDOW_SIZE_x),
									root.size.y/float(DEFAULT_WINDOW_SIZE_y)))

func on_window_unfocused() -> void:
	Engine.set_max_fps(WindowUtils.get_oof_fps_cap())

func on_window_focused() -> void:
	Engine.set_max_fps(WindowUtils.get_game_fps_cap() if is_3D_scene() else WindowUtils.get_menu_fps_cap())

func get_root_last_child() -> Node:
	return root.get_child(root.get_child_count() - 1)

func get_root() -> Window:
	return get_tree().get_root()

func refresh_root() -> void:
	root = get_root()

func refresh_tree() -> void:
	tree = get_tree()
#	refresh_root()

func get_mp() -> MultiplayerAPI:
	return tree.get_multiplayer()

func get_local_mp_id() -> int:
	# same as get_mp().get_unique_id()
	if multiplayer:
		return multiplayer.get_unique_id()
	else:
		return 1

func get_current_scene() -> Node:
	return tree.current_scene

func get_nodes_in_group(group: StringName) -> Array[Node]:
	return tree.get_nodes_in_group(group)

func get_current_camera() -> Camera3D:
	return root.get_camera_3d()

func change_scene(scene: String) -> void:
	var gaming: Error = tree.change_scene_to_file(scene)
	Console.get_assertfail_msg(gaming == OK,"Changing scene got error %s."%error_string(gaming),true)
	# Below is the single dumbest line of code in this file, maybe the whole project.
	# Yes, this is on purpose. Yes, this works. This is a real thing that you really
	# have to do if you want to use Godot's SceneTree change_scene_to_file function.
	# Now, you might ask yourself. Why not just do it manually? idk lol it literally
	# does it all in one frame but I trust that either eventually this will be worked
	# out in an engine update or that maybe something is better abt using the engine
	# function as-is. idk tho lololol
	# https://forum.godotengine.org/t/change-scene-to-file-current-scene-returns-null-instance-after-switching-to-new-scene/105648
	# NOTE: as of 6/2/25, I've made it so that if the current scene is null,
	# on_scene_changed just gets called again and again every frame until there's
	# a valid current scene. So as such, this line is no longer needed. But I'm keeping
	# it around as is in case on_scene_changed either gets changed in the future, and alos
	# as a reminder of how changing scenes works
	defer_to_next_frame(defer_to_next_frame.bind(on_scene_changed))

func change_scene_to_node(node: Node) -> void:
	tree.unload_current_scene()
	root.add_child(node)
	tree.set_current_scene(node) # Changed from get_root_last_child(), which seems obvious but maybe it was there for a good reason idk
	defer_to_next_frame(on_scene_changed)

func is_3D_scene() -> bool:
	if !get_current_scene():
		Console.push_err("Current scene is null. Fuck!")
	return get_current_scene() is Node3D

# Originally this was called deferredand it seemed to work fine but I
# guess something changed...?
func on_scene_changed() -> void:
	if !get_current_scene():
		return defer_to_next_frame(on_scene_changed)
#	tree.set_multiplayer_poll_enabled(!tree.current_scene is MultiplayerLevel)
	if is_3D_scene():
		WindowUtils.go_game_settings()
		GraphicsSettings.apply_environment_settings()
	else:
		WindowUtils.go_menu_settings()
	on_window_resized()
	TimeUtils.check_func_time(setup_window_focuses.bind(root))

# Maybe put these in WindowUtils?
func setup_window_focuses(node: Node) -> void:
	for child in node.get_children(true):
		if child is Window and child != Console:
			setup_window_focus(child as Window)
		setup_window_focuses(child)
	#for window in root.get_embedded_subwindows():
		#Console.write(window.name)
		#if window != Console:
			#setup_window_focus(window)

func setup_window_focus(window: Window) -> void:
	window.focus_entered.connect(on_window_focused)

func quit() -> void:
#	Settings.save_settings()
	tree.quit()

static func get_datetime_string() -> String:
	return Time.get_datetime_string_from_system(false, true).replace(":", "-")

static func global_orientation(obj: Node3D) -> Vector3:
	# tbh normailizing this changes like basically nothing so maybe its not worth doing
	# example: changes (-0.318499, -0.088899, 0.943740) into (-0.318501, -0.088899, 0.943745)
	return obj.global_transform.basis.z.normalized()

# could be static
func is_exported() -> bool:
	return !OS.has_feature("editor")

static func is_timer_running(timer: Timer) -> bool:
	# if a timer is inactive it also returns 0, so this works no matter what :)
	return false if timer.get_time_left() == 0.0 else true

static func get_dict_from_array(array: Array) -> Dictionary:
	var dict: Dictionary = {}
	for idx in array.size():
		dict[idx] = array[idx]
	return dict

static func apply_array_to_dict(dict: Dictionary, array: Array) -> void:
	for idx in array.size():
		dict[idx] = array[idx]

static func types_are_same(var1: Variant, var2: Variant) -> bool:
	return typeof(var1) == typeof(var2)

func setup_subwindow_size(subwindow: Window, size: Vector2i) -> void:
	if root.size.x < size.x:
		size.x = root.size.x - 60
	if root.size.y < size.y:
		size.y = root.size.y - 60
	subwindow.set_size(size)
	if subwindow.position.x > root.size.x or subwindow.position.x < root.position.x:
		subwindow.position.x = root.size.x - subwindow.size.x - 20
	if subwindow.position.y > root.size.y or subwindow.position.y < root.position.y:
		subwindow.position.y = root.size.y - subwindow.size.y - 20

static func print_meta_list_for_node_and_children(node: Node) -> void:
	for child in node.get_children():
		print("--------------")
		print(child.get_name())
		print("--------------")
		print(child.get_meta_list())
		print("-------------------------------")
		print_meta_list_for_node_and_children(child)
		print("-------------------------------")

static func get_func_length(function: Callable) -> int:
	var time2: int
	var time: int = Time.get_ticks_usec()
	function.call()
	time2 = Time.get_ticks_usec()
	return time2 - time

static func get_filename_without_extension(path: String) -> String:
	return path.get_file().rstrip(path.get_extension())

static func disconnect_all_signals(obj: Object, object_filter: Array[Object] = []) -> void:
	for sig in obj.get_signal_list():
		disconnect_all_signal_connections(obj,sig.name,object_filter)

static func disconnect_all_connections(sig: Signal) -> void:
	for connection in sig.get_connections():
		sig.disconnect(connection.callable as Callable)

static func disconnect_all_signal_connections(obj: Object, sig: String, object_filter: Array[Object] = []) -> void:
	var connections: Array[Dictionary] = obj.get_signal_connection_list(sig)
	if object_filter.is_empty():
		for connection in connections:
			obj.disconnect(sig,connection.callable)
	else:
		for connection in connections:
			var callable: Callable = connection.callable
			if object_filter.has(callable.get_object()):
				obj.disconnect(sig,callable)
				Console.write_in_color("Disconnecting "+callable.get_method(),Color.PURPLE)
			else:
				Console.write_in_color("Not disconnecting "+callable.get_method(),Color.MAROON)

static func signal_disconnect_all_connections(sig: Signal) -> void:
	var connections: Array[Dictionary] = sig.get_connections()
	for connection in connections:
		sig.disconnect(connection.callable)

static func connect_signal_if_not_already(sig: Signal, callable: Callable) -> void:
	if !sig.is_connected(callable):
		sig.connect(callable)

static func disconnect_signal_if_connected(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)

static func suspend_signal_connection(sig: Signal, callable: Callable, suspension_end_signal: Signal) -> void:
	assert(sig.is_connected(callable), "Signal %s must be connected to callable %s in order to suspend its connection."%[sig,callable])
	assert(callable.get_object() != null, "Callable %s must be connected to an object in order for signal to suspend its connection."%[callable])
	
	sig.disconnect(callable)
	
	suspension_end_signal.connect(sig.get_object().connect.bind(sig.get_name(),callable),CONNECT_ONE_SHOT)

func remove_node(node: Node) -> void:
	var instance_id: int = node.get_instance_id()
	node.get_parent().remove_child.call_deferred(node)
	removed_nodes[instance_id] = node
	removed_node_ids[node] = instance_id

func reinsert_node(node: Node, parent: Node) -> void:
	parent.add_child(node)
	var instance_id: int = removed_node_ids[node]
	erase_node_from_dicts(node,instance_id)

func erase_node_from_dicts(node: Node, instance_id: int) -> void:
	removed_nodes.erase(instance_id)
	removed_node_ids.erase(node)

func reinsert_node_by_id(instance_id: int, parent: Node) -> void:
	var node: Node = removed_nodes[instance_id]
	parent.add_child(node)
	erase_node_from_dicts(node,instance_id)

func is_removed_node_properly_set_up(node: Node) -> String:
	if !removed_node_ids.has(node):
		return "Removed node IDs does not contain an ID for node %s."%node
	if !removed_nodes.has(removed_node_ids[node]):
		return "Removed nodes does not contain node %s's ID of %s."%[node,removed_node_ids[node]]
	if removed_nodes[removed_node_ids[node]] != node:
		return "Removed nodes node %s matches node %s's ID key of %s."%[removed_nodes[removed_node_ids[node]],node,removed_node_ids[node]]
	return ""

func free_removed_node(node: Node) -> void:
	assert(is_removed_node_properly_set_up(node).is_empty(),is_removed_node_properly_set_up(node))
	node.free()
	erase_node_from_dicts(node,removed_node_ids[node])

func queue_free_removed_node(node: Node) -> void:
	node.queue_free()
	erase_node_from_dicts(node,removed_node_ids[node])

func connect_to_timer(timer_len: float, callable: Callable, flags: int = 0) -> int:
	return tree.create_timer(timer_len).timeout.connect(callable,flags)

func assert_valid_number_of_users() -> void:
	assert(num_users < 5 and num_users > 0,"%s is an invalid number of users. Number of users must be less than 5 or greater than 0."%[num_users])

func connect_callable_to_frame_starts(callable: Callable, flags: int = 0) -> void:
	tree.process_frame.connect(callable,flags)
	tree.physics_frame.connect(callable,flags)

func disconnect_callable_from_frame_starts(callable: Callable) -> void:
	tree.process_frame.disconnect(callable)
	tree.physics_frame.disconnect(callable)

func connect_callable_to_frame_start_if_out_of_time(callable: Callable, max_time: float = 0.95) -> void:
	if not TimeUtils.is_frame_out_of_time(max_time):
		return
	connect_callable_to_frame_starts(callable)
	# on frame start, disconnect callable from proc/phys
	connect_callable_to_frame_starts(disconnect_callable_from_frame_starts.bind(callable))
	# on frame start, disconnect disconnection callable from proc/phys
	connect_callable_to_frame_starts(disconnect_callable_from_frame_starts.bind(disconnect_callable_from_frame_starts))

func await_if_out_of_time(max_frame_frac: float = 0.95,sig: Signal = tree.process_frame) -> bool:
	if TimeUtils.is_frame_out_of_time(max_frame_frac):
		await sig
	return true

func await_process_frame(method: Callable) -> bool:
	await tree.process_frame
	method.call()
	return true

func await_physics_frame(method: Callable) -> bool:
	await tree.physics_frame
	method.call()
	return true

static func request_ready_recursive(node: Node) -> void:
	node.request_ready()
	for child in node.get_children(true):
		request_ready_recursive(child)

func add_debug_boxmesh(transform: Transform3D, time: float = 3., custom_extents := Vector3(.05,.05,.05)) -> void:
	var bm := BoxMesh.new()
	bm.size = custom_extents
	spawn_debug_mesh(bm,transform,time)

var raycast_debug_mesh: StandardMaterial3D = (func() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.set_shading_mode(BaseMaterial3D.SHADING_MODE_UNSHADED)
	mat.set_flag(BaseMaterial3D.FLAG_DISABLE_FOG,true)
	mat.set_cull_mode(BaseMaterial3D.CULL_DISABLED)
	mat.set_transparency(BaseMaterial3D.TRANSPARENCY_ALPHA)
	mat.set_albedo(Color.GREEN)
	return mat).call() as StandardMaterial3D

var raycast_colliding_debug_mesh: StandardMaterial3D = (func() -> StandardMaterial3D:
	var mat := raycast_debug_mesh.duplicate()
	mat.set_albedo(Color.RED)
	return mat).call() as StandardMaterial3D

func spawn_debug_raycast_mesh(raycast: RayCast3D, time: float = 3.) -> MeshInstance3D: # time: float = ProjectSettings.get_setting_safe("quack/debug/collision_shape_default_time",3.) as float
	var mesh := ArrayMesh.new()
	var verts: PackedVector3Array = [Vector3.ZERO,raycast.target_position]
	var array: Array
	array.resize(Mesh.ARRAY_MAX)
	array[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,array)
	mesh.surface_set_material(0,raycast_colliding_debug_mesh if raycast.is_colliding() else raycast_debug_mesh)
	return spawn_debug_mesh(mesh,raycast.global_transform,time)

func draw_line(start: Vector3, end: Vector3, lifetime: float, color := Color.PURPLE) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var mat := StandardMaterial3D.new()
	mat.set_shading_mode(BaseMaterial3D.SHADING_MODE_UNSHADED)
	mat.set_flag(BaseMaterial3D.FLAG_DISABLE_FOG,true)
	mat.set_cull_mode(BaseMaterial3D.CULL_DISABLED)
	mat.set_transparency(BaseMaterial3D.TRANSPARENCY_ALPHA)
	mat.set_albedo(color)
	var verts: PackedVector3Array = [start,end]
	var array: Array
	array.resize(Mesh.ARRAY_MAX)
	array[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,array)
	mesh.surface_set_material(0,mat)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	get_current_scene().add_child(node)
	node.add_to_group(&"Debug Collision Shapes")
	tree.create_timer(lifetime,true,true,false).timeout.connect(node.queue_free,CONNECT_ONE_SHOT)
	return node

func spawn_debug_mesh(mesh: Mesh, transform: Transform3D, time: float = 3.) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.ready.connect(node.set_global_transform.bind(transform))
	get_current_scene().add_child(node)
	node.add_to_group(&"Debug Collision Shapes")
	# BUG: for some fucking reason this last arg in create_timer, which supposedly
	# ignores timescale makes this timer take way fucking longer. FIXME! It should
	# ignore timescale, but for now I'm setting it so that it doesn't.
	tree.create_timer(time,true,true,false).timeout.connect(node.queue_free,CONNECT_ONE_SHOT)
	return node

func can_add_debug_mesh() -> bool:
	return ProjectSettings.get_setting_safe("quack/debug/show_collisions",false)

func can_add_debug_ray() -> bool:
	return ProjectSettings.get_setting_safe("quack/debug/show_rays",false)

const DEFAULT_DEBUG_COLLISION_COLOR = Color("0099b36b")
const DEFAULT_DEBUG_COLLISION_VERTEX_COLOR = Color(0.0, 0.6, 0.698, 0.0235)

func spawn_colldier_debug_mesh(collider: CollisionShape3D, time: float = ProjectSettings.get_setting_safe("quack/debug/collision_shape_default_time",3.) as float) -> MeshInstance3D:
	 # Scenetreetimers in physics frames are bugged and assume that it's the
	# default tickrate or whatever. this might cause issues if the game ever
	# launches with a non 60hz physics framerate.
	var mesh := collider.shape.get_debug_mesh()
	return spawn_debug_mesh(mesh,collider.global_transform,time)# / (60. / Engine.physics_ticks_per_second))

func spawn_recolored_debug_mesh(mesh: Mesh, color: Color, transform: Transform3D, time: float) -> MeshInstance3D:
	mesh = mesh.duplicate()
	var mdt := MeshDataTool.new()
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) == Mesh.PrimitiveType.PRIMITIVE_TRIANGLES:
			@warning_ignore("confusable_local_declaration")
			var err := mdt.create_from_surface(mesh,surface)
			if err != OK:
				Console.push_err("Editing surface %s of mesh %s with color %s returned error %s upon creating from surface."%[
					surface,mesh,color,error_string(err)
				])
				continue
			#await Quack.await_physics_frame(mdt.create_from_surface.bind(mesh,surface))
			mesh.surface_remove(surface)
		else:
			pass
			# TODO actually apply color
	#var task := WorkerThreadPool.add_group_task(mdt.set_vetex_color.bind(color),mdt.get_vertex_count(),-1,true,)
	for vertex in mdt.get_vertex_count():
		mdt.set_vertex_color(vertex,color)
	var err := mdt.commit_to_surface(mesh)
	if err != OK:
		Console.push_err("Editing mesh %s with color %s returned error %s upon committing to surface."%[
			mesh,color,error_string(err)
		])
	return spawn_debug_mesh(mesh,transform,time)

func spawn_recolored_colldier_debug_mesh(collider: CollisionShape3D, color: Color = DEFAULT_DEBUG_COLLISION_VERTEX_COLOR, time: float = ProjectSettings.get_setting_safe("quack/debug/collision_shape_default_time",3.) as float) -> MeshInstance3D:
	return spawn_recolored_debug_mesh(collider.shape.get_debug_mesh(),color,collider.global_transform,time)

func spawn_debug_mesh_child(collider: CollisionShape3D, interp: bool = false) -> void:
	Stupid4pt5Mesh.new(collider,interp)

class Stupid4pt5Mesh extends MeshInstance3D:
	var parent_collider: CollisionShape3D
	func _init(collider: CollisionShape3D, interp := false) -> void:
		mesh = collider.shape.get_debug_mesh()
		parent_collider = collider
		if interp:
			physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		else:
			physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			top_level = true
		process_mode = Node.PROCESS_MODE_PAUSABLE
		collider.add_child(self)
	
	func _physics_process(_delta: float) -> void:
		if top_level:
			update_transform.call_deferred()
	
	func update_transform() -> void:
		global_transform = parent_collider.global_transform

func is_node_valid(node: Variant) -> bool:
	if node == null: return false
	if node.is_queued_for_deletion() or !is_instance_valid(node): return false
	return true

func defer_to_next_frame(callable: Callable) -> void:
	tree.process_frame.connect(callable,CONNECT_ONE_SHOT)

func defer_to_next_physics_frame(callable: Callable) -> void:
	tree.physics_frame.connect(callable,CONNECT_ONE_SHOT)

var impact_mesh: ArrayMesh = (func() -> ArrayMesh:
	var sphere := SphereShape3D.new()
	sphere.radius = .05
	return sphere.get_debug_mesh()).call() as ArrayMesh
