extends Timer

const Serializer = preload("res://gameplay/serializer.gd")
const OwnerID = preload("res://gameplay/owner_id.gd")
var serializer: Serializer

var time: float

func _notification(what: int) -> void:
	if not Quack.Network.is_node_local(owner):
		return
	match what:
		NOTIFICATION_INTERNAL_PHYSICS_PROCESS:
			if process_callback == TIMER_PROCESS_PHYSICS:
				time = time_left
		NOTIFICATION_INTERNAL_PROCESS:
			if process_callback == TIMER_PROCESS_IDLE:
				time = time_left

func _ready() -> void:
	await owner.ready
	Serializer.component_list[owner].updated.connect(on_updated)

func on_updated() -> void:
	if Quack.Network.is_node_local(owner) and not paused: # checking if not paused is redundant
		start(time)
