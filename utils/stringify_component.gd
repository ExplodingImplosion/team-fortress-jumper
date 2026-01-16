@tool
extends Label3D

@export_range(0,10,.001,"or_greater") var update_rate: float = 0.
@export var physics: bool = true
@export var process: bool = true
@export var to_str: bool = false
var time_physics: float
var time_process: float

func _ready() -> void:
	if !OS.is_debug_build(): queue_free(); return;
	stringify_parent()

func _physics_process(delta: float) -> void:
	if physics:
		time_physics += delta
		if time_physics >= update_rate:
			stringify_parent()
			time_physics = 0

func _process(delta: float) -> void:
	if process:
		time_process += delta
		if time_process >= update_rate:
			stringify_parent()
			time_process = 0

func stringify_parent() -> void:
	text = var_to_str(get_parent()) if to_str else str(get_parent())
