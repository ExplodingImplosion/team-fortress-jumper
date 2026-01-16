const SplitscreenViewport = preload("res://interface/splitscreen/splitscreen_viewport.gd")
const ViewportManager = preload("res://interface/splitscreen/splitscreen_viewport_manager.gd")
const QuackPlayer = preload("res://network/multiplayer/player.gd")
const MultiplayerSession = preload("res://network/multiplayer/multiplayer_session.gd")

const splitscreen_scenes: Array[Array] = [
	# 2
	[
		preload("res://interface/splitscreen/splitscreen_configs/2_player/2_player_tall_splitscreen.tscn"),
		preload("res://interface/splitscreen/splitscreen_configs/2_player/2_player_splitscreen.tscn"),
	],
	# 3
	[
		preload("res://interface/splitscreen/splitscreen_configs/3_player/3_player_lr_splitscreen.tscn"),
		preload("res://interface/splitscreen/splitscreen_configs/3_player/3_player_splitscreen.tscn"),
		preload("res://interface/splitscreen/splitscreen_configs/3_player/3_player_tall_splitscreen.tscn")
	],
	# 4
	[
		preload("res://interface/splitscreen/splitscreen_configs/4_player/4_player_splitscreen.tscn"),
	],
	# 5
	[
		preload("res://interface/splitscreen/splitscreen_configs/5_player/5_player_splitscreen.tscn"),
	],
	# 6
	[
		preload("res://interface/splitscreen/splitscreen_configs/6_player/6_player_splitscreen.tscn"),
	],
	# 7
	[
		preload("res://interface/splitscreen/splitscreen_configs/7_player/7_player_splitscreen.tscn"),
	],
	# 8
	[
		preload("res://interface/splitscreen/splitscreen_configs/8_player/8_player_splitscreen.tscn"),
	],
	
]

const SPLITSCREEN_SETTINGS_PATH = "quack/splitscreen/"
const PREFER_WIDER_VIEWPORTS_PATH = SPLITSCREEN_SETTINGS_PATH + "prefer_wider_viewports"
const ODD_NUM_VIEWPORTS_PREFERRED_PLAYER_NUM_PATH = SPLITSCREEN_SETTINGS_PATH + "odd_num_viewports_preferred_player_num"
const PREFERRED_PLAYER_GETS_PREFERRED_VIEWPORT_STYLE_PATH = SPLITSCREEN_SETTINGS_PATH + "preferred_player_gets_preferred_viewport_style"
const SCREENS_TO_POPOUT_PATH = SPLITSCREEN_SETTINGS_PATH + "screens_to_popout"

enum SplitscreenMode {
	SUB_VIEWPORT,
	SEPARATE_WINDOW
}

enum PreferWiderViewportsMode {
	AUTO,
	ON,
	OFF
}

static var viewports: Dictionary[Player,SplitscreenViewport] = {}
static var sub_viewports: Array[SubViewport]
static var windows: Array[Window]
static var manager: ViewportManager

static func apply_render_scale(render_scale: float) -> void:
	for viewport in manager.viewports:
		viewport.set_scaling_3d_scale(render_scale)

static func apply_to_all_viewports(method: StringName, ...args) -> void:
	for viewport in manager.viewports:
		viewport.callv(method,args)

static func start_splitscreen() -> void:
	assert(not manager, "Tried to start splitscreen while manager was %s and not null!"%manager)
	assert(MultiplayerSession.local_client, "There needs to be a local client to do splitscreen")
	
	#var local_client := MultiplayerSession.local_client
	#var popouts := get_screens_to_pop_out()
	
	manager = (splitscreen_scenes[Quack.num_users-2][0] as PackedScene).instantiate() as ViewportManager
	Quack.root.add_child(manager)
	Quack.root.disable_3d = true
	apply_render_scale(Quack.root.get_scaling_3d_scale())
	
	#for i in Quack.num_users:
		#var splitscreen_viewport := SplitscreenViewport.create_window(local_client.players[i]) if popouts & 1<<i else SplitscreenViewport.create_splitscreen_viewport(local_client.players[i])
		#manager.add_child(splitscreen_viewport.viewport)

static func cleanup_splitscreen() -> void:
	if manager:
		stop_splitscreen()

static func stop_splitscreen() -> void:
	assert(manager != null, "Tried to stop splitscreen while manager was null!")
	manager.queue_free()
	manager = null
	Quack.root.disable_3d = false

static func get_prefer_wider_viewports() -> bool:
	var setting := ProjectSettings.get_setting_safe(PREFER_WIDER_VIEWPORTS_PATH,PreferWiderViewportsMode.AUTO) as PreferWiderViewportsMode
	match setting:
		PreferWiderViewportsMode.AUTO:
			match sub_viewports.size():
				1:
					return true
				2:
					return true
				3:
					return true
				4:
					return true
				5:
					return true
				6:
					return false
				7:
					return true
				8:
					return false
				_:
					Console.get_assertfail_msg(false,"Invalid number of sub viewports %s."%sub_viewports.size(),true)
					return true
		PreferWiderViewportsMode.ON:
			return true
		PreferWiderViewportsMode.OFF:
			return false
		_:
			Console.get_assertfail_msg(false,"invalid prefer wider viewports mode %s."%setting,true)
			return true

static func get_preferred_player_gets_preferred_viewport_style() -> bool:
	return ProjectSettings.get_setting_safe(PREFERRED_PLAYER_GETS_PREFERRED_VIEWPORT_STYLE_PATH,false) as bool

static func get_odd_num_viewports_preferred_player_num() -> int:
	return ProjectSettings.get_setting_safe(ODD_NUM_VIEWPORTS_PREFERRED_PLAYER_NUM_PATH,0) as int

static func get_screens_to_pop_out() -> int:
	return ProjectSettings.get_setting_safe(SCREENS_TO_POPOUT_PATH,0) as int
