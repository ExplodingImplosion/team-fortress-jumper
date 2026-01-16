extends Node

signal mouse_moved(relative: Vector2)
signal pause_pressed

class StickInput:
	# lmfao bad name
	const controller_input_curve = preload("res://utils/controller_input_curve.tres")
	const controller_response_curve = preload("res://utils/controller_response_curve.tres")
	signal stick_inputted(relative: Vector2)
	var up: StringName
	var down: StringName
	var left: StringName
	var right: StringName
	var sens: float
	var scope_factor: float
	var scoped: bool
	var scope_scale: float = 1.
	var time_max_len: float = 0.
	
	func get_scope_relative_sens() -> float:
		return sens if not scoped else sens * scope_scale * scope_factor
	
	func _init(player_index: int) -> void:
		var suffix := "_"+str(player_index) if player_index else ""
		up = "analog_look_up"+suffix
		down = "analog_look_down"+suffix
		left = "analog_look_left"+suffix
		right = "analog_look_right"+suffix
		
		if player_index > 0:
			sens = default_input_profile.csens * 40
			scope_factor = default_input_profile.scope_factor
	
	func process(delta: float) -> void:
		var vector := Input.get_vector(left,right,up,down)
		if vector:
			#vector.x = controller_response_curve.sample(vector.x)
			#vector.y = controller_response_curve.sample(vector.y)
			if vector.length() >= .95:
				time_max_len += delta
				vector *= controller_input_curve.sample(time_max_len)
			else:
				time_max_len = 0.
			stick_inputted.emit(vector * delta * get_scope_relative_sens())
		else:
			time_max_len = 0.

var sticks: Array[StickInput] = [
	StickInput.new(0),
	StickInput.new(1),
	StickInput.new(2),
	StickInput.new(3),
	StickInput.new(4),
	StickInput.new(5),
	StickInput.new(6),
	StickInput.new(7),
]
var mouse_player_idx: int = 0
var mouse_player_stick_input: StickInput = sticks[mouse_player_idx]
var mouse_inputs: Dictionary[StringName,InputEvent]

var gameplay_inputs_paused: bool = false
var gameplay_input_blockers: int = 0
func pause_gameplay_inputs() -> void:
	gameplay_input_blockers += 1
	gameplay_inputs_paused = true
	@warning_ignore("static_called_on_instance")
	Inputs.show_cursor()

func resume_gameplay_inputs() -> void:
	gameplay_input_blockers -= 1
	gameplay_inputs_paused = gameplay_input_blockers > 0
	assert(gameplay_input_blockers >= 0, "Somethings gone wrong if this went negative")
	if not gameplay_inputs_paused:
		if Inputs.is_mouse_connected_to_object():
			@warning_ignore("static_called_on_instance")
			Inputs.capture_cursor()

const ProcessPriorities = Quack.ProcessPriorities
func _init() -> void:
	ProcessPriorities.set_singleton(self)

const MAX_NUM_PLAYERS = 8
var num_players_registered: int
func _ready() -> void:
	sticks.make_read_only()
	register_all_actions()
	register_splitscreen_actions()
	var stick := sticks[0]
	stick.sens = getcsens() * 40
	stick.scope_factor = get_c_scope_factor()

func register_splitscreen_actions() -> void:
	var unregistered_actions: Array[StringName]
	var player_idx: int
	for i in 7: # Player 1 has regular without a suffix
		# originally this func looped backwards so that, basically, if it turned
		# out that player 4 had all their actions registered, then players 2 and
		# 3 probably already had their actions registered, too. But tbh, since
		# actions might be renamed, added or removed, and because this func only
		# runs occasionally, most often on startup, I'm just gonna check every
		# player anyway.
		player_idx = MAX_NUM_PLAYERS-1-i
		var idx_string := StringName("_"+str(player_idx))
		unregistered_actions = get_unregistered_actions(idx_string)
		if !unregistered_actions.is_empty():
			for action in unregistered_actions:
				if OS.is_debug_build():
					Console.writeverb(action)
				register_splitscreen_action(action,player_idx,idx_string)

func register_splitscreen_action(action: StringName, idx: int, idx_str: StringName) -> void:
	InputMap.add_action(action)
	if default_input_profile.actions.has(action.trim_suffix(idx_str)):
		for event in default_input_profile.actions[action.trim_suffix(idx_str)].events:
			if event is InputEventMouse or event is InputEventKey or event is InputEventAction:
				continue
			var new_event: InputEvent = (event as InputEvent).duplicate()
			new_event.device = idx
			InputMap.action_add_event(action,new_event)
		#if is_just_pressed_action(action):
			#add_splitscreen_action_to_map(action,idx_str,just_pressed_button_actions_map)
	if !is_analog_action(action):
		add_splitscreen_action_to_map(action,idx_str,button_actions_map)

static func add_splitscreen_action_to_map(action: StringName, idx_str: StringName, map: Dictionary) -> void:
	map[action] = map[action.trim_suffix(idx_str)]

func is_mouse_connected_to_object() -> bool:
	return false if mouse_moved.get_connections().is_empty() else true

static func show_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

static func capture_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

static func is_mouse_captured() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

static func showhide_cursor_on_ui_cancel() -> void:
	if Input.is_action_just_pressed(&"ui_cancel"):
		showhide_cursor()

static func showhide_cursor() -> void:
	@warning_ignore("standalone_ternary")
	capture_cursor() if is_mouse_visible() else show_cursor()

static func is_mouse_visible() -> bool:
#	return true if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE else false
	match Input.get_mouse_mode():
		Input.MOUSE_MODE_VISIBLE:
			return true
		Input.MOUSE_MODE_CONFINED:
			return true
		_:
			return false

@warning_ignore("static_called_on_instance")
@onready var sens: float = getsens() * .01
@onready var scope_factor: float = get_scope_factor()

const CONTROLS_SETTINGS_PATH = "quack/controls/"
const MOUSE_SETTINGS_PATH = CONTROLS_SETTINGS_PATH + "mouse/"
const CONTROLLER_SETTINGS_PATH = CONTROLS_SETTINGS_PATH + "controller/"
const KEYBOARD_SETTINGS_PATH = CONTROLS_SETTINGS_PATH + "keyboard/"

const SENS_STRING = "sensitivity"
const SCOPE_FACTOR_STRING = "scope_sensitivity_scale_factor"

const SENS_SETTING = MOUSE_SETTINGS_PATH + SENS_STRING
const SCOPE_FACTOR_SETTING = MOUSE_SETTINGS_PATH + SCOPE_FACTOR_STRING

const CSENS_SETTING = CONTROLLER_SETTINGS_PATH + SENS_STRING
const C_SCOPE_FACTOR_SETTING = CONTROLLER_SETTINGS_PATH + SCOPE_FACTOR_STRING

const KSENS_SETTING = KEYBOARD_SETTINGS_PATH + SENS_STRING
const K_SCOPE_FACTOR_SETTING = KEYBOARD_SETTINGS_PATH + SCOPE_FACTOR_STRING

static func getsens() -> float:
	return ProjectSettings.get_setting_safe(SENS_SETTING,5.)

static func get_scope_factor() -> float:
	return ProjectSettings.get_setting_safe(SCOPE_FACTOR_SETTING,1.)

static func getcsens() -> float:
	return ProjectSettings.get_setting_safe(CSENS_SETTING,5.)

static func get_c_scope_factor() -> float:
	return ProjectSettings.get_setting_safe(C_SCOPE_FACTOR_SETTING,1.)

static func getksens() -> float:
	return ProjectSettings.get_setting_safe(KSENS_SETTING,2.)

static func get_k_scope_factor() -> float:
	return ProjectSettings.get_setting_safe(K_SCOPE_FACTOR_SETTING,1.)

func get_scope_relative_sens() -> float:
	return sens if not mouse_player_stick_input.scoped else sens * mouse_player_stick_input.scope_scale * mouse_player_stick_input.scope_factor

func change_sens(newsens: float) -> void:
	ProjectSettings.set_setting(SENS_SETTING, newsens)
	sens = newsens * 0.01

func change_csens(newsens: float) -> void:
	ProjectSettings.set_setting(CSENS_SETTING,newsens)
	Inputs.sticks[0].sens = newsens * 40

func _process(delta: float) -> void:
	if gameplay_inputs_paused: return
	for input in sticks:
		input.process(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if !gameplay_inputs_paused:
			mouse_moved.emit((event as InputEventMouseMotion).relative*get_scope_relative_sens())
	#elif event is InputEventJoypadMotion:
		#pass
	elif Input.is_action_just_pressed(&"ui_pause"):
		pause_pressed.emit()

enum {UP, DOWN}

static func action_pressed_as_bitflag(action: StringName, this_int: int) -> int:
	return this_int if Input.is_action_pressed(action) else UP

static func action_just_pressed_as_bitflag(action: StringName, this_int: int) -> int:
	return this_int if Input.is_action_just_pressed(action) else UP

var button_actions: Array[StringName]
var button_actions_map: Dictionary[StringName,int] = {}
#var just_pressed_button_actions: Array[StringName]
#var just_pressed_button_actions_map: Dictionary[StringName,int] = {}
var total_num_actions: int

func is_gameplay_action_pressed(action: StringName, exact_match := false) -> bool:
	return Input.is_action_pressed(action,exact_match) and !gameplay_inputs_paused

func is_gameplay_action_just_pressed(action: StringName, exact_match := false) -> bool:
	return Input.is_action_just_pressed(action,exact_match) and !gameplay_inputs_paused

func is_gameplay_action_just_released(action: StringName, exact_match := false) -> bool:
	return Input.is_action_just_released(action,exact_match) and !gameplay_inputs_paused

func get_keyboard_updowns(player_idx: int) -> int:
	var suffix := StringName(str(player_idx)) if player_idx > 0 else &""
	if gameplay_inputs_paused: return 0
	var updowns: int = 0
	var num_button_actions: int = button_actions.size()
	for action in num_button_actions:
		updowns |= action_pressed_as_bitflag(button_actions[action] + suffix, 1<<action)
	#for action in just_pressed_button_actions.size():
		#updowns |= action_just_pressed_as_bitflag(just_pressed_button_actions[action] + suffix, 1<<(action+num_button_actions))
	return updowns

#func get_button_pressed(button: StringName) -> int:
	#return 1<<button_actions_map[button]
#func get_button_just_pressed(button: StringName) -> int:
	#return 1<<(button_actions.size()+just_pressed_button_actions_map[button])

const left = &"analog_left"
const right = &"analog_right"
const forward = &"analog_forward"
const back = &"analog_back"

func get_movement_from_keyboard(player_idx: int) -> Vector2:
	var suffix := StringName(str(player_idx)) if player_idx > 0 else &""
	if gameplay_inputs_paused: return Vector2.ZERO
	return Input.get_vector(left+suffix,right+suffix,forward+suffix,back+suffix) * (1.0 - 0.5 * int(Input.is_action_pressed(&"walk")))

const analog_prefix = "analog"
const ui_prefix = "ui_"
#const just_pressed_prefix = "just_pressed_"

## Returns if a string begins with "analog_"
static func is_analog_action(action: StringName) -> bool:
	return action.begins_with(analog_prefix)

### Returns if a string begins with "just_pressed_"
#static func is_just_pressed_action(action: StringName) -> bool:
	#return action.begins_with(just_pressed_prefix)

static func is_ui_action(action: StringName) -> bool:
	return action.begins_with(ui_prefix)

## Returns if a string is an acceptable game-related button input [param action] by
## determining if the button is prefixed with a ui-related, analog-related, or
## player_move-related string. If [param action] meets the criteria of [method is_ui_action],
## [method is_analog_action], or [method is_player_move_action], the function
## returns false.
static func is_game_button_action(action: StringName) -> bool:
	return not (is_ui_action(action) or is_analog_action(action) or Console.command_string_map.has(action))

## Called once when the game starts up. Registers all game-related
## button actions in [member action_events]/[member action_bitfields] and
## [member just_pressed_action_events]/[member just_pressed_action_bitfields] by
## parsing through [method InputMap.get_actions], and adding each action if it
## [method is_game_button_action].
func register_all_actions() -> void:
	for action in InputMap.get_actions():
		if get_script().is_game_button_action(action):
			#if get_script().is_just_pressed_action(action):
				#just_pressed_button_actions.append(action)
				#just_pressed_button_actions_map[action] = just_pressed_button_actions.size() - 1
			#else:
			button_actions.append(action)
			button_actions_map[action] = button_actions.size() - 1
	total_num_actions = button_actions.size()# + just_pressed_button_actions.size()

func get_unregistered_actions(idx_str: StringName) -> Array[StringName]:
	var unregistered_actions: Array[StringName]
	add_unregistered_actions(idx_str,unregistered_actions,button_actions)
	#add_unregistered_actions(idx_str,unregistered_actions,just_pressed_button_actions)
	# lmao
	unregistered_actions.append(left+idx_str)
	unregistered_actions.append(right+idx_str)
	unregistered_actions.append(forward+idx_str)
	unregistered_actions.append(back+idx_str)
	unregistered_actions.append(&"analog_look_up"+idx_str)
	unregistered_actions.append(&"analog_look_down"+idx_str)
	unregistered_actions.append(&"analog_look_left"+idx_str)
	unregistered_actions.append(&"analog_look_right"+idx_str)
	unregistered_actions.append(&"analog_move_mod"+idx_str) # old, maybe delete
	return unregistered_actions

func add_unregistered_actions(idx: StringName, add_to: Array[StringName], add_from: Array[StringName]) -> void:
	for action in add_from:
		action += idx
		if !InputMap.has_action(action):
			add_to.append(action)

func register_actions_for_splitscreen_player(idx: int) -> void:
	var idx_str := StringName(str(idx))
	for action in get_unregistered_actions(idx_str):
		register_splitscreen_action(action,idx,idx_str)

func get_button_action_idx(action: StringName) -> int:
	return (button_actions_map[action] as int)

#func get_just_pressed_button_action_idx(action: StringName) -> int:
	#return (just_pressed_button_actions_map[action] as int)

func register_key_for_action(key: String, action: StringName) -> void:
	var event := InputEventKey.new()
	var keycode := OS.find_keycode_from_string(key)
	if keycode == KEY_NONE:
		return Console.writerr("Invalid key %s."%key)
	event.set_physical_keycode(keycode)
	if InputMap.action_has_event(action,event):
		Console.writerr("Action %s is already bound to button %s."%[action,key])
	else:
		InputMap.action_add_event(action,event)
		save_input_action(action)

func save_input_action(action: StringName) -> void:
	var setting_path: String = get_action_setting_path(action)
	var events := InputMap.action_get_events(action)
	var setting: Dictionary = ProjectSettings.get_setting(setting_path,{"deadzone": 0.5, "events": events})
	if setting.events != events:
		setting.events = events
	ProjectSettings.set_setting(setting_path,setting)

func get_action_setting_path(action: StringName) -> String:
	return "input/"+action

# a lotta these could be static lmao
func remove_action(key: String, action: StringName) -> void:
	var event := get_key_event(key)
	if InputMap.action_has_event(action,event):
		remove_action_event(action,event)
	else:
		Console.writerr("Action %s is not bound to button %s."%[action,key])

func remove_action_event(action: StringName, event: InputEvent) -> void:
	assert(InputMap.action_has_event(action,event), "Action %s must have event %s in order to remove it."%[action,event]) # could be InputMap.event_is_action(event,action)
	InputMap.action_erase_event(action,event)
	save_input_action(action)
	if Console.command_string_map.has(String(action)):
		if InputMap.action_get_events(action).is_empty():
			InputMap.erase_action(action)
			ProjectSettings.clear(get_action_setting_path(action))
			Console.shortcuts.erase(action)

func remove_key_from_all_actions(key: String) -> void:
	var event := get_key_event(key)
	var action_unbinded: bool
	for action in InputMap.get_actions():
		if InputMap.event_is_action(event,action):
			Console.write("Unbinding key %s from action %s."%[key,action])
			remove_action_event(action,event)
			action_unbinded = true
	if !action_unbinded:
		Console.writerr("Key %s not bound to any actions."%key)

func get_key_event(key: String) -> InputEventKey:
	var event := InputEventKey.new()
	event.set_physical_keycode(OS.find_keycode_from_string(key))
	return event

const default_input_profile = preload("res://utils/default_input_profile.tres")

const INPUT_BUFFER_SIZE = 120
const MOUSE_MOVEMENT_OWNER_PLAYER_IDX = "quack/gameplay/mouse_movement_owner_player_idx"
var input_signature: int
class PlayerInputs:
	
	var updowns: int
	var just_pressed_updowns: int
	var aim_angle: Vector2
	var input_dir: Vector2
	var frame_hint: int
	var firing_interp_fraction: float
	
	#func _init() -> void:
		#pass
	
	func encode(buffer: NetworkedNode.StreamPeerBitBuffer) -> void:
		for i in Inputs.total_num_actions:
			buffer.put_bool(updowns&(1<<i))
			buffer.put_bool(just_pressed_updowns&(1<<i))
		buffer.put_rv2_half(aim_angle)
		buffer.put_half(input_dir.x)
		buffer.put_half(input_dir.y)
		buffer.put_n16(firing_interp_fraction)
		buffer.put_u32(frame_hint)
	
	func decode(buffer: NetworkedNode.StreamPeerBitBuffer) -> void:
		updowns = 0
		just_pressed_updowns = 0
		for i in Inputs.total_num_actions:
			updowns |= (1<<i)*int(buffer.get_bool())
			just_pressed_updowns |= (1<<i)*int(buffer.get_bool())
		aim_angle = buffer.get_rv2_half()
		input_dir = Vector2(buffer.get_half(),buffer.get_half())
		firing_interp_fraction = snappedf(buffer.get_n16(),.001)
		frame_hint = buffer.get_u32()
	
	func is_action_pressed(action: StringName) -> bool:
		return updowns & 1<<Inputs.button_actions_map[action]
	
	func is_action_just_pressed(action: StringName) -> bool:
		return just_pressed_updowns & 1<<Inputs.button_actions_map[action]
	

func get_player_inputs(player: Quack.Network.MultiplayerSession.QuackPlayer) -> PlayerInputs:
	return player.get_input() if player else PlayerInputs.new()
