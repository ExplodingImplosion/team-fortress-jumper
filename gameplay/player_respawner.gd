extends Node

const PlayerCharacter = preload("res://player/Player.tscn")
const NetworkBoundingBoxComponent = preload("res://gameplay/network_bounding_box_component.gd")
const Network = Quack.Network
const MPSession = Network.MultiplayerSession
const QuackPlayer = MPSession.QuackPlayer
const QuackMultiplayer = Network.QuackMultiplayer
const OwnerID = Network.OwnerID
const SplitscreenViewports = preload("res://interface/splitscreen/splitscreen_viewport_manager.gd")
const Splitscreen = SplitscreenViewports.Splitscreen

@export var respawn_time: float = 5.

@export var spawnpoints: Array[Marker3D]

@export var player_scene: PackedScene
@export var weapons: Array[PackedScene]

var queue: Dictionary[Player,float]
var spawn_idx: int = 0

func _ready() -> void:
	if Quack.Network.is_server():
		for player:QuackPlayer in MPSession.players.values():
			initial_spawn_player.call_deferred(player)
		MPSession.player_readied.connect(initial_spawn_player)
	else:
		queue_free()

func add_player_to_respawn_queue(component: Player) -> void:
	Console.write("Adding %s to respawn queue."%component.name)
	queue[component] = respawn_time

func _physics_process(delta: float) -> void:
	for component:Player in queue.keys():
		var time := queue[component]
		time -= delta
		if time <= 0.:
			respawn_player(component)
		else:
			queue[component] = time

func initial_spawn_player(player: Player) -> void:
	for node in OwnerID.get_nodes_owned_by(player.id):
		if node.scene_file_path == player_scene.resource_path:
			return # Player already has existing node in the scene
	var character := player_scene.instantiate() as Node3D
	var transform := get_spawnpoint_transform()
	QuackMultiplayer.set_node_position_on_ready(character,transform.origin)
	character.ready.connect(character.force_update_transform)
	get_parent().add_child.call_deferred(character)
	character.reset_physics_interpolation.call_deferred()
	OwnerID.add_node_owner.call_deferred(character,player.id)

func respawn_player(component: Player) -> void:
	queue.erase(component)
	component.global_transform = get_spawnpoint_transform()
	component.velocity = Vector3.ZERO
	component.reset_physics_interpolation()
	if component.owned_locally:
		OwnerID.get_node_player_owner(component).aim_angle.x = component.global_rotation.y
	component.undie()
	if NetworkBoundingBoxComponent.component_list.has(component.mesh):
		NetworkBoundingBoxComponent.component_list[component.mesh].fill_states.call_deferred()
	#if HealthComponent.component_list.has(player):
		#var health := HealthComponent.component_list[player]
		#health.set_health(health.max_health)
	#if InventoryComponent.component_list.has(player):
		#var inventory := InventoryComponent.component_list[player]
		#for scene in weapons:
			#inventory.weapon_removed.connect(Console.console_commands_script.free_node,CONNECT_REFERENCE_COUNTED)
			#inventory.add_weapon(scene.instantiate() as Weapon)

func get_spawnpoint_transform() -> Transform3D:
	var spawnpoint := spawnpoints[spawn_idx]
	spawn_idx = wrapi(spawn_idx+1,0,spawnpoints.size())
	return spawnpoint.global_transform
