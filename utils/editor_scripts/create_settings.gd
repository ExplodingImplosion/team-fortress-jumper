@tool
extends EditorScript

const PERF_OVERLAY_SETTING_PATH = "quack/performance_overlay/readouts/"
var perfoverlay: GDScript = load("res://interface/perf_overlay/perf_overlay.gd")
func _run() -> void:
	update_perf_overlay()
	#dump_environment()
	#print_setting_paths()
	#setup_settings()
	#add_new_settings()
	save_settings()

func setup_settings() -> void:
	settings = [
	NewSetting.new(
		"quack/network/client/maximum_command_frame_rate",
		0,
		PROPERTY_HINT_RANGE,
		"0,300,1"
	),
	NewSetting.new(
		"quack/network/client/preferences/buffer_time",
		0.,
		PROPERTY_HINT_RANGE,
		"0,0.2,0.001"
	),
	NewSetting.new(
		"quack/network/client/preferences/input_buffer_time",
		0.,
		PROPERTY_HINT_RANGE,
		"0,0.2,0.001"
	),
	NewSetting.new(
		"quack/network/client/preferences/server_input_buffer_time",
		0.,
		PROPERTY_HINT_RANGE,
		"0,0.2,0.001"
	),
	NewSetting.new(
		"quack/network/client/bandwidth/max_receive_bandwidth",
		0,
		PROPERTY_HINT_RANGE,
		"0,6250000,1"
	),
	NewSetting.new(
		"quack/network/client/bandwidth/max_send_bandwidth",
		0,
		PROPERTY_HINT_RANGE,
		"0,6250000,1"
	),
	NewSetting.new(
		"quack/network/host/maximum_command_frame_rate",
		0,
		PROPERTY_HINT_RANGE,
		"0,300,1"
	),
	NewSetting.new(
		"quack/network/host/minimum_input_buffer_time",
		0.,
		PROPERTY_HINT_RANGE,
		"0,0.2,0.001"
	),
	NewSetting.new(
		"quack/network/host/minimum_latency",
		0.,
		PROPERTY_HINT_RANGE,
		"0,1,0.001"
	),
	NewSetting.new(
		"quack/network/host/bandwidth/max_receive_bandwidth",
		0,
		PROPERTY_HINT_RANGE,
		"0,6250000,1"
	),
	NewSetting.new(
		"quack/network/host/bandwidth/max_send_bandwidth",
		0,
		PROPERTY_HINT_RANGE,
		"0,6250000,1"
	),]

func dump_environment() -> void:
	var env := ClassDB.class_get_property_list(&"Environment",true)
	settings.clear()
	var groups: Dictionary[String,String]
	var subgroups: Dictionary[String,String]
	for p in env:
		if p.usage == PROPERTY_USAGE_GROUP:
			var group := (p.name as String).to_snake_case()
			groups[p.hint_string] = ENV+group+"/"
		elif p.usage == PROPERTY_USAGE_SUBGROUP:
			var group := groups.keys()[-1] as String
			var subgroup := (p.name as String).to_snake_case()
			subgroups[group+"_"+subgroup] = ENV+groups[group]+subgroup+"/"
	print("Groups:")
	for group in groups:
		print(group,": ",groups[group])
	print("\nSubgroups:")
	for subgroup in subgroups:
		print(subgroup,": ",subgroups[subgroup])
	print("\nSettings:")
	for p in env:
		if p.usage != PROPERTY_USAGE_DEFAULT or p.type == TYPE_OBJECT:
			continue
		#print(p.name,":")
		#for key in p.keys():
			#if key as String != "name":
				#print("	",key,": ",p[key])
		var p_group: String
		var name: String = p.name as String
		var path: String = get_setting_path(name,subgroups)
		if path == ENV + name:
			path = get_setting_path(name,groups)
		print(path)
		settings.append(
			NewSetting.new(
				path,
				ClassDB.class_get_property_default_value(&"Environment",name),
				p.hint,
				p.hint_string
			)
		)
	add_new_settings()

func get_setting_path(name: String, groups: Dictionary[String,String]) -> String:
	for group in groups:
		if name.begins_with(group):
			return groups[group]+name.trim_prefix(group)
	return ENV + name

class NewSetting:
	var path: String
	var value: Variant
	var type: Variant.Type
	var hint: PropertyHint
	var hint_string: String
	
	enum {
		NAME,VALUE,TYPE,HINT,HINT_STRING
	}
	
	func _init(setting: String, val: Variant, h: PropertyHint, hs: String) -> void:
		path = setting
		value = val
		type = typeof(val)
		hint = h
		hint_string = hs
	
	func to_dict() -> Dictionary[String,Variant]:
		return {
			"name": path,
			"type": type,
			"hint": hint,
			"hint_string": hint_string
		}
	
	static func from_array(array: Array) -> void:
		NewSetting.new(array[NAME],array[VALUE],array[HINT],array[HINT_STRING]).apply_setting()
	
	func _to_string() -> String:
		return "Path: %s
Value: %s
Type: %s
Hint: %s
Hint String: %s"%[path,value,type,Quack.ByteUtils.to_binary_string(hint),hint_string]
	
	func apply_setting() -> void:
		ProjectSettings.set_setting(path,value)
		ProjectSettings.add_property_info(to_dict())

const QUACK = "quack/"
const GRAPHICS = QUACK+"graphics/"
const ENV = GRAPHICS + "environment/"
const TONEMAP = ENV + "tonemap/"
static var settings: Array[NewSetting] = []
#const settings: Array[Array] = [
	#[TONEMAP+"exposure",Environment.ToneMapper.TONE_MAPPER_FILMIC,],
#]
func print_setting_paths() -> void:
	var map := (Quack.Network as Script).get_script_constant_map()
	for constant in map.keys():
		if (constant as StringName).ends_with("SETTING_PATH"):
			print(map[constant]) if map[constant] is String else null

func add_new_settings() -> void:
	print("\n","Setting configs:")
	for setting in settings:
		print(setting,"\n")
		setting.apply_setting()


func update_perf_overlay() -> void:
	for property in perfoverlay.get_script_property_list():
		if is_script_variable(property):
			if property.class_name == &"Label" or property.class_name == &"ProgressBar":
				add_setting(property.name)

func save_settings() -> void:
	var err := OK#ProjectSettings.save_custom("user://override.cfg")
	if err != OK:
		printerr("Couldn't save settings. Got error %s."%error_string(err))
	else:
		print("Successfully saved override.cfg.")
	err = ProjectSettings.save()
	if err != OK:
		printerr("Couldn't save settings. Got error %s."%error_string(err))
	else:
		print("Successfully saved project.godot.")

	# Hint strings don't add tooltips. Cool!
	#add_hint_string("quack/controls/mouse/sensitivity","Controls how much a first or third person camera is rotated in proportion to mouse movement.")
	#add_hint_string("quack/video/resolution/game_resolution","What resolution the game's window will set itself to while in gameplay (3D) scenes.")
	#add_hint_string("quack/video/resolution/menu_resolution","What resolution the game's window will set itself to while in menu (non-gameplay, 2D) scenes.")
	#add_hint_string("quack/video/framerate/game_framerate","What framerate the game will attempt to run at while in gameplay (3D) scenes.")
	#add_hint_string("quack/video/framerate/menu_framerate","What framerate the game will attempt to run at while in menu, (non-gameplay, 2D) scenes.")
	#add_hint_string("quack/video/framerate/out_of_focus_framerate","What framerate the game will attempt to run at while its window is not in focus (i.e. when the game is clicked off of on a computer, while alt-tabbed on Windows, or while swiping to a different app/the home screen on mobile.)")
	#add_hint_string("quack/audio/volume/master_voume","Globally scales all of the game's volume by a multiplier between 0 and 1.")
	#add_hint_string("quack/video/fullscreen/game_fullscreen","What window format the game uses while in gameplay (3D) scenes.")
	#add_hint_string("quack/video/fullscreen/menu_fullscreen","What window format the game uses while in menu (non-gameplay, 2D) scenes.")
	#add_hint_string("quack/performance_overlay/size/font_size","What font size the performance overlay uses.")
	#add_hint_string("quack/performance_overlay/size/max_width","The maximum width, in pixels, that the performance overlay will occupy horizontally. 0 sets it to the same as the game's current resolution.")
	#add_hint_string("quack/gameplay/number_of_players","How many players are playing the game.")
	#add_hint_string("quack/network/maximum_command_frame_rate","This is an advanced setting. The maximum number of inputs and gameplay acknowledgements this device will attempt to send to a host or server in a given second. 0 is unlimited.")
	#add_hint_string("quack/network/preferred_buffer_size","This is an advanced setting. The preferred number of inputs that a host or server will hold in a buffer before executing them in-game. Higher values will significantly reduce the risk of missed/duplicated inputs, at the cost of guaranteed additional input latency. At a simulation rate of 60, each frame corresponds to an additional minimum of 16ms of lag.")
	#add_hint_string("quack/network/max_receive_bandwidth","The maximum amount of bandwidth, in ___ per second that this device will receive.")
	#add_hint_string("quack/network/max_send_bandwidth","The maxmimum amount of bandwidth, in ___ per second that this device will send.")
	#add_hint_string("quack/console/transparency","Controls the transparency of the developer console's window. This applies ONLY to the console's BACKGROUND. Text transparency is NOT affected.")
	#add_hint_string("quack/console/write_max_frame_duration","This is an advanced setting. The maximum amount of time the game will spend on non-critical tasks. Higher numbers can cause issues with performance on lower end devices, and lower numbers can cause numerous side effects.")
	#add_hint_string("quack/performance_overlay/readouts/fpsreadout",polabelblurb%"the engine's FPS counter")
	#add_hint_string("quack/performance_overlay/readouts/interpreadout",polabelblurb%"the current fraction between physics frames")
	#add_hint_string("quack/performance_overlay/readouts/deltareadout",polabelblurb%"the engine's process frame delta time")
	#add_hint_string("quack/performance_overlay/readouts/physdeltareadout",polabelblurb%"the engine's physics frame delta time")
	#add_hint_string("quack/performance_overlay/readouts/quackphysdeltareadout",polabelblurb%"the game's physics frame delta time")
	#add_hint_string("quack/performance_overlay/readouts/quackdeltareadout",polabelblurb%"the game's process frame delta time")
	#add_hint_string("quack/performance_overlay/readouts/processtimereadout",polabelblurb%"how long the engine has measured it's taking to execute process frames")
	#add_hint_string("quack/performance_overlay/readouts/physprocesstimereadout",polabelblurb%"how long the engine has measured it's takingto execute physics frames")
	#add_hint_string("quack/performance_overlay/readouts/processdeltatimediffreadout",polabelblurb%"the difference between process delta and process time")
	#add_hint_string("quack/performance_overlay/readouts/processquackdeltadiffreadout",polabelblurb%"the difference between Quack physics delta and physics time")
	#add_hint_string("quack/performance_overlay/readouts/physicsprocesstimedeltadiffreadout",polabelblurb%"the difference between physics delta and physics time")
	#add_hint_string("quack/performance_overlay/readouts/physicsprocessratereadout",polabelblurb%"how long Quack thinks it took to simulate the last physics frame, in ms")
	#add_hint_string("quack/performance_overlay/readouts/netupdateratereadout",polabelblurb%"how long it's been since the game has last received a gameplay packet")
	#add_hint_string("quack/performance_overlay/readouts/physicsnetdiffreadout",polabelblurb%"the difference between net update rate and physics process rate")
	#add_hint_string("quack/performance_overlay/readouts/physicsprocessoffsetreadout","This one is really stupid, ignore it.")
	#add_hint_string("quack/performance_overlay/readouts/netupdateoffsetreadout","This one is also really stupid, ignore it.")
	#add_hint_string("quack/performance_overlay/readouts/physicsprocessnetupdateoffsetreadout","This one is even dumber! Ignore it!")
	#add_hint_string("quack/performance_overlay/readouts/quackfpsreadout",polabelblurb%"1 / Quack FPS")
	#add_hint_string("quack/performance_overlay/readouts/framedelayreadout",polabelblurb%"How far behind the host or server, in physics frames, the device is viewing the game state")
	#add_hint_string("quack/performance_overlay/readouts/timebehindserverreadout",polabelblurb%"How far behind the host or server, in ms, the device is viewing the game state")
	#add_hint_string("quack/performance_overlay/readouts/netinputdelayreadout",polabelblurb%"How many inputs that the device has made that have not been acknowledged by the host or server")
	#add_hint_string("quack/performance_overlay/readouts/serverbufferreadout",polabelblurb%"How many inputs that the device has made that the host or server has in its input buffer")
	#add_hint_string("quack/performance_overlay/readouts/totalinputdelayreadout",polabelblurb%"The difference, in number of inputs, that the client has made that the host or server has not executed yet")
	#add_hint_string("quack/performance_overlay/readouts/advancedfpsreadout",polabelblurb%"The exact number of process frames executed within the last second")
	#add_hint_string("quack/performance_overlay/readouts/cpurenderreadout",polabelblurb%"How long the engine says it took the CPU to get rendering work ready for the most recent rendered frame, in ms")
	#add_hint_string("quack/performance_overlay/readouts/gpurenderreadout",polabelblurb%"How long the engine says it took the GPU to render the most recent rendered frame, in ms")
	#add_hint_string("quack/performance_overlay/readouts/framesetupreadout",polabelblurb%"How long the engine says it took the CPU to set up getting rendering ready for the most recent rendered frame, in ms")
	#add_hint_string("quack/performance_overlay/readouts/renderfpsreadout",polabelblurb%"How long the engine says it would, without gameplay and other engine logic, take to render the most recent rendered frame, in seconds")
	#add_hint_string("quack/performance_overlay/readouts/interpbarreadout",polabelblurb%"a visualization of interp")
	#add_hint_string("quack/performance_overlay/color",polabelblurb%"the performance overlay's font color")
	#add_hint_string("quack/console/text_max_frame_duration_before_deferrment","This is an advanced setting. The maximum amount of time the game will spend on rendering new console text. Higher numbers can cause issues with performance on lower end devices, and lower numbers can cause the console to display larger amounts of text over several seconds, and sometimes certain lines of text will appear out-of-order.")
	#add_hint_string("quack/console/shortcuts","This is an advanced setting, and probably not one that should be edited directly. Which console commands have had shortcuts created for them.")

const polabelblurb = "Controls appearance of a readout showing %s in the performance overlay."

func add_setting_advanced(setting: String, value: Variant, hint: PropertyHint = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	if ProjectSettings.has_setting(setting):
		ProjectSettings.add_property_info(get_property_info_dict(setting,ProjectSettings.get_setting(setting),hint,hint_string))
	else:
		ProjectSettings.set_setting(setting,value)
		ProjectSettings.add_property_info(get_property_info_dict(setting,value,hint,hint_string))

func add_hint_string(setting: String, hint_string: String) -> void:
	if ProjectSettings.has_setting(setting):
		print(get_property_info_dict(setting,ProjectSettings.get_setting(setting),PROPERTY_HINT_NONE,hint_string))
		ProjectSettings.add_property_info(get_property_info_dict(setting,ProjectSettings.get_setting(setting),PROPERTY_HINT_NONE,hint_string))
	else:
		printerr("Can't add hint string to setting %s. Setting doesn't exist."%setting)

func get_property_info_dict(setting: String, value: Variant, hint: PropertyHint = PROPERTY_HINT_NONE, hint_string: String = "") -> Dictionary:
	return {
		"name": setting,
		"type": typeof(value),
		"hint": hint,
		"hint_string": hint_string
	}

func add_setting(setting: String) -> void:
	if !ProjectSettings.has_setting(PERF_OVERLAY_SETTING_PATH + setting):
		ProjectSettings.set_setting(PERF_OVERLAY_SETTING_PATH + setting,true)
		print("Setting %s didn't exist in file, applying and saving."%setting)
	else:
		print("Setting %s exists."%setting)

func is_script_variable(property_info: Dictionary) -> bool:
	return property_info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE
