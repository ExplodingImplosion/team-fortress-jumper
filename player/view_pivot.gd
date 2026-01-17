extends Node3D

const YAW_LIMIT = 1.55334 # 89 degrees up and down.

#@export_range(0, 1, 0.001, "radians_as_degrees") var sensitivity := deg_to_rad(0.075)
var height_offset := 68 * Player.HU

@onready var camera: Camera3D = $Camera

@onready var parent := get_parent()
var local := false
var player: Quack.Network.MultiplayerSession.QuackPlayer

func _handle_camera_rotation(relative: Vector2):
	rotation.y = wrapf(rotation.y - deg_to_rad(relative.x), -PI, PI)
	rotation.x = clampf(rotation.x - deg_to_rad(relative.y), -YAW_LIMIT, YAW_LIMIT)
	if local:
		player.aim_angle = Vector2(rotation.y,rotation.x)

func _process(_delta: float) -> void:
	global_position = get_parent_node_3d().get_global_transform_interpolated().origin + Vector3(0.0, height_offset, 0.0)

func on_owner_changed() -> void:
	local = Quack.Network.is_node_local(parent)
	player = Quack.Network.OwnerID.get_node_player_owner(parent)
	if local:
		Inputs.capture_cursor()
		Inputs.mouse_moved.connect(_handle_camera_rotation)

func _physics_process(_delta: float) -> void:
	if player:
		var aa := player.get_input().aim_angle
		rotation.y = aa.x
		rotation.x = aa.y
