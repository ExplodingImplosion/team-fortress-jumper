@icon("res://shared/icons/tf.png")
extends Node3D


const DEPLOY_TIME = 0.5

@export var tp: Node3D
@export var fp: Node3D

@export var primary_weapon: WeaponNode
@export var secondary_weapon: WeaponNode
@export var melee_weapon: WeaponNode

@export var held_weapon: WeaponNode: set = switch_to
var held_idx: int


@onready var deploy_timer: Timer = $Deploy


func process_inputs(inputs: Inputs.PlayerInputs):
	if inputs.is_action_pressed("player_switch_to_primary"):
		switch_to_by_path(primary_weapon.get_path())
	elif inputs.is_action_pressed("player_switch_to_secondary"):
		switch_to_by_path(secondary_weapon.get_path())
	elif inputs.is_action_pressed("player_switch_to_melee"):
		switch_to_by_path(melee_weapon.get_path())
	elif inputs.is_action_pressed("player_switch_to_4"):
		switch_to_by_path("GrenadeLauncher")

func _physics_process(_delta: float) -> void:
	var inputs := Inputs.get_player_inputs(Quack.Network.OwnerID.get_node_player_owner(owner))
	if inputs:
		process_inputs(inputs)

func _ready() -> void:
	deploy_timer.timeout.connect(activate_held_weapon)
	
	var fp_anim_player: AnimationPlayer = fp.get_node("AnimationPlayer")
	var tp_anim_tree: AnimationTree = tp.get_node("AnimationTree")
	for wep: WeaponNode in get_weapons():
		wep.holster()
		if wep.fp_model:
			_prepare_weapon_model(wep.fp_model, true)
		if wep.tp_model:
			_prepare_weapon_model(wep.tp_model, false)
		
		wep.first_person_player = fp_anim_player
		# Bleh. Why do we "inject" first_player_player to the weapons but not the third person one?
		if wep.type != WeaponNode.Type.EQUIPPABLE:
			wep.deployed.connect(tp_anim_tree._on_any_weapon_deployed.bind(wep.type))
			wep.shot.connect(tp_anim_tree._on_any_weapon_shot)

func on_updated() -> void:
	if held_idx != get_weapon_index(held_weapon):
		switch_to(get_weapon_by_index(held_idx))

func get_weapon_by_index(idx: int) -> WeaponNode:
	match idx:
		0:
			return primary_weapon
		1:
			return secondary_weapon
		2:
			return melee_weapon
	return null

func get_weapon_index(weapon: WeaponNode) -> int:
	match weapon:
		primary_weapon:
			return 0
		secondary_weapon:
			return 1
		melee_weapon:
			return 2
	return -1

func switch_to_by_path(path: NodePath):
	switch_to(get_node(path))

func switch_to(wep: WeaponNode):
#	print("From ", held_weapon, " to ", wep)
	if held_weapon == wep:
		return
	
	if held_weapon:
		held_weapon.active = false
		held_weapon.holster()
	
	held_weapon = wep
	
	if not is_node_ready(): 
		await ready # At the beginning, the timer isn't quite inside the tree.
	deploy_timer.start(DEPLOY_TIME)
	
	if held_weapon:
		held_weapon.deploy()
		held_idx = get_weapon_index(held_weapon)
	else:
		Console.writerr("Switched to holding no weapon!")
	

func activate_held_weapon():
	assert(held_weapon)
	held_weapon.active = true


func get_weapons() -> Array[WeaponNode]:
	var result: Array[WeaponNode]
	result.assign(get_children().filter(func(child): return child is WeaponNode))
	return result


func _prepare_weapon_model(model: Node3D, for_first_person := false):
	# Nasty assumptions galore.
	assert(model.get_child_count() > 0)
	assert(model.get_child(0).get_child(0) is MeshInstance3D)
	
	var root_person: Node3D = (fp if for_first_person else tp)
	var skeleton_node: Skeleton3D = (fp.get_node("FPSkeleton") if for_first_person else tp.get_node("TPSkeleton"))
	var mesh_instance: MeshInstance3D = model.get_child(0).get_child(0)
	
	mesh_instance.skeleton = ""; # Prevent an error before reparenting.
	model.reparent(root_person, false)
	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton_node)
	
	if not for_first_person:
		model.rotation.y += PI # TPSkeleton is flipped, too.
	
	# Missing bones cause errors. Void the invalid binds.
	var skin: Skin = mesh_instance.skin.duplicate()
	mesh_instance.skin = skin
	for bind in skin.get_bind_count():
		if skeleton_node.find_bone(skin.get_bind_name(bind)) == -1:
			# FIXME: This is not right for the Shovel.
			skin.set_bind_name(bind, "")
			skin.set_bind_bone(bind, 2)
