const Client = preload("res://network/multiplayer/client.gd")
const QuackPlayer = preload("res://network/multiplayer/player.gd")

var client: Client
var id: int
var idx: int
var team: int
var spectating: bool
var camera: Camera3D
var action_suffix: String
var input_buffer: Array[Inputs.PlayerInputs]
var aim_angle: Vector2

func _init(client_owner: Client, player_index: int) -> void:
	client = client_owner
	idx = player_index
	id = client.id + idx
	if player_index:
		action_suffix = "_%s"%player_index
	input_buffer.resize(Quack.Network.input_buffer_size)
	for i in Quack.Network.input_buffer_size:
		input_buffer[i] = Inputs.PlayerInputs.new()
	Client.Network.MultiplayerSession.player_added.emit(self)
	if client.ready:
		Client.Network.MultiplayerSession.player_readied.emit(self)

func get_input(prev_frame_offset: int = 0) -> Inputs.PlayerInputs:
	return input_buffer[wrapi(client.input_buffer_offset-prev_frame_offset,0,Inputs.INPUT_BUFFER_SIZE)]

func get_input_by_signature(signature: int = client.input_signature) -> Inputs.PlayerInputs:
	return get_input(client.input_signature-signature)

func apply_local_inputs() -> void:
	var inputs := get_input()
	for i in Inputs.total_num_actions:
		if Inputs.is_gameplay_action_pressed(Inputs.button_actions[i]+action_suffix):
			inputs.updowns |= 1<<i
		else:
			inputs.updowns &= ~(1<<i)
	for i in Inputs.total_num_actions:
		if Inputs.is_gameplay_action_just_pressed(Inputs.button_actions[i]+action_suffix):
			inputs.just_pressed_updowns |= 1<<i
		else:
			inputs.just_pressed_updowns &= ~(1<<i)
	inputs.input_dir = Input.get_vector(
		"analog_left"+action_suffix,
		"analog_right"+action_suffix,
		"analog_forward"+action_suffix,
		"analog_back"+action_suffix
	) * int(not Inputs.gameplay_inputs_paused)
	inputs.aim_angle = aim_angle
	inputs.frame_hint = client.most_recent_received_frame.u32_frame if client.most_recent_received_frame else client.most_recent_acked_frame.num
