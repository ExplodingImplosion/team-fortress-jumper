extends CanvasLayer

const LabelUtils = preload("res://utils/label_utils.gd")
const TimeUtils = Quack.TimeUtils
const Network = Quack.Network
const Tickrate = Quack.Tickrate
const PanelBackground = preload("res://interface/perf_overlay/perf_overlay_background.tres")
const ProcessPriorities = preload("res://utils/process_priorities.gd")

#const ENABLEDSETTINGPATH = "quack/performance_overlay/enabled"
const WIDTHSETTINGPATH = "quack/performance_overlay/size/max_width"
const FONTSIZESETTINGPATH = "quack/performance_overlay/size/font_size"
const COLORSETTINGPATH = "quack/performance_overlay/color"
const NOTISSETTINGSPATH = "quack/performance_overlay/notifications"
const BACKGROUNDSETTINGPATH = "quack/performance_overlay/readouts_background"
const READOUTSETTINGPATH = "quack/performance_overlay/readouts/"

var measured_rids: Array[RID] = [Quack.root.get_viewport_rid()]

var visible_settings: PackedStringArray
var labels: Array[Control]

var client: Network.MultiplayerSession.Client

func _ready() -> void:
	containercontainer.size.x = max_width if max_width > 0 else Quack.root.size.x
	# maybe optimize this in the future
	setup_visibility_settings()
	apply_visibility_settings()
	frame_hist.resize(Engine.max_fps if Engine.max_fps == 0 else 300)
	process_priority = ProcessPriorities.Process.Priorities.PERF_OVERLAY
	process_physics_priority = ProcessPriorities.Physics.Priorities.PERF_OVERLAY

func setup_visibility_settings() -> void:
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.class_name == &"Label" or property.class_name == &"ProgressBar":
			visible_settings.append(property.name)
	labels.resize(visible_settings.size())
	var parent: Control
	var setting: Control
	for i in visible_settings.size():
		setting = get(visible_settings[i]) as Control
		parent = setting.get_parent() as Control
		if parent == containercontainer:
			labels[i] = setting
		else:
			labels[i] = parent

signal visibility_idle
var idle_frame: int
func apply_visibility_settings() -> void:
	var update_color: bool = color != Color.WHITE
	var has_background: bool = (ProjectSettings.get_setting_safe(BACKGROUNDSETTINGPATH,true) as bool)
	var panel: StyleBox = PanelBackground if has_background else null
	container.set(&"theme_override_constants/h_separation",0 if has_background else 5)
	for i in visible_settings.size():
		var f: int = Engine.get_process_frames()
		if f > idle_frame:
			visibility_idle.emit.call_deferred()
			await visibility_idle
			idle_frame = f
		
		labels[i].visible = ProjectSettings.get_setting_safe(READOUTSETTINGPATH+visible_settings[i],true)
		
		if not labels[i].visible: continue # skip extra stuff for invisible labels
		
		# maybe it would be faster to see if child count = 0
		if labels[i] is Label:
			update_font_size(labels[i] as Label)
			continue
		
		var is_readout: bool
		for label in labels[i].get_children():
			if label is Label:
				update_font_size(label)
				if has_background:
					LabelUtils.remove_font_shadow(label)
				else:
					LabelUtils.set_font_shadow_color(label,Color.BLACK)
				if is_readout:
					label.custom_minimum_size.x = font_size * (label.visible_characters + 1) / 2
				#if update_color:
				update_font_color(label)
				LabelUtils.set_style(label,panel)
			is_readout = true
		#Console.write("%s %s"%[TimeUtils.get_frame_frac_remainder(), idle_frame])
		await Quack.await_if_out_of_time()
	# lmao
	if interpbarreadout.is_visible():
		(interpbarreadout.get(&"theme_override_styles/fill") as StyleBoxFlat).bg_color = color
		interpbarreadout.custom_minimum_size.y = (interpbarreadout.get_parent().get_child(0) as Label).size.y
	toggle_client_readouts(multiplayer.get_unique_id() > 1)

func update_font_size(label: Label) -> void:
	LabelUtils.set_font_size(label,font_size)

func update_font_color(label: Label) -> void:
	LabelUtils.set_font_color(label,color)

var client_readouts_on: bool = false
var packet_peer: ENetPacketPeer
var last_epoch: float
func toggle_client_readouts(on: bool) -> void:
	if on:
		client = Network.MultiplayerSession.local_client
	client_readouts_on = on
	bigserverbuffernoti.visible = on
	if on:
		packet_peer = Network.peer.get_host().get_peers()[0]
	else:
		packet_peer = null
		for readout in client_readouts:
			(readout.get_parent() as HBoxContainer).visible = false

func add_viewport(viewport: Viewport) -> void:
	var rid := viewport.get_viewport_rid()
	measured_rids.append(rid)
	RenderingServer.viewport_set_measure_render_time(rid,true)
	viewport.tree_exiting.connect(measured_rids.erase.bind(rid),CONNECT_ONE_SHOT)
	viewport.tree_exiting.connect(RenderingServer.viewport_set_measure_render_time.bind(rid,false))

func _enter_tree() -> void:
	Quack.root.size_changed.connect(assign_width_to_root_width)
	Quack.multiplayer.connected_to_server.connect(apply_visibility_settings)
	Quack.multiplayer.server_disconnected.connect(apply_visibility_settings)
	if Quack.Splitscreen.manager:
		for viewport in Quack.Splitscreen.manager.viewports:
			measured_rids.append(viewport.get_viewport_rid())
			viewport.tree_exiting.connect(measured_rids.erase.bind(viewport.get_viewport_rid()),CONNECT_ONE_SHOT)
	for rid in measured_rids:
		RenderingServer.viewport_set_measure_render_time(rid,true)
func _exit_tree() -> void:
	Quack.root.size_changed.disconnect(assign_width_to_root_width)
	Quack.multiplayer.connected_to_server.disconnect(apply_visibility_settings)
	Quack.multiplayer.server_disconnected.disconnect(apply_visibility_settings)
	for rid in measured_rids:
		RenderingServer.viewport_set_measure_render_time(rid,false)

func assign_width_to_root_width() -> void:
	var root_width: int = Quack.root.size.x
	if root_width < max_width or max_width == 0:
		containercontainer.size.x = root_width
	elif containercontainer.size.x != max_width:
		containercontainer.size.x = max_width

#@onready var topcontainer: HBoxContainer = $topcontainer
#@onready var fpscontainer: HBoxContainer = $topcontainer/fpscontainer

@onready var containercontainer: VBoxContainer = $containercontainer as VBoxContainer
@onready var container: HFlowContainer = $containercontainer/container as HFlowContainer
@onready var max_width: int = ProjectSettings.get_setting_safe(WIDTHSETTINGPATH,container.size.x)
@onready var font_size: int = ProjectSettings.get_setting_safe(FONTSIZESETTINGPATH,12)
@onready var color: Color = ProjectSettings.get_setting_safe(COLORSETTINGPATH,Color.WHITE)

@onready var fpsreadout: Label = ($containercontainer/container/fpscontainer/readout as Label)
@onready var interpreadout: Label = ($containercontainer/container/interpcontainer/readout as Label)
@onready var interpbarreadout: ProgressBar = ($containercontainer/container/interpbarcontainer/readout as ProgressBar)
@onready var deltareadout: Label = ($containercontainer/container/deltacontainer/readout as Label)
@onready var physdeltareadout: Label = ($containercontainer/container/physdeltacontainer/readout as Label)
@onready var quackphysdeltareadout: Label = ($containercontainer/container/quackphysdeltacontainer/readout as Label)
@onready var quackdeltareadout: Label = ($containercontainer/container/quackdeltacontainer/readout as Label)
@onready var processtimereadout: Label = ($containercontainer/container/processtimecontainer/readout as Label)
@onready var physprocesstimereadout: Label = ($containercontainer/container/physprocesstimecontainer/readout as Label)
@onready var processdeltatimediffreadout: Label = ($containercontainer/container/processdeltatimediffcontainer/readout as Label)
@onready var processquackdeltadiffreadout: Label = ($containercontainer/container/processquackdeltadiffcontainer/readout as Label)
@onready var physicsprocesstimedeltadiffreadout: Label = ($containercontainer/container/physicsprocesstimedeltadiffcontainer/readout as Label)
@onready var physicsprocessratereadout: Label = ($containercontainer/container/physicsprocessratecontainer/readout as Label)
@onready var netupdateratereadout: Label = ($containercontainer/container/netupdateratecontainer/readout as Label)
@onready var physicsnetdiffreadout: Label = ($containercontainer/container/physicsnetdiffcontainer/readout as Label)
@onready var physicsprocessoffsetreadout: Label = ($containercontainer/container/physicsprocessoffsetcontainer/readout as Label)
@onready var netupdateoffsetreadout: Label = ($containercontainer/container/netupdateoffsetcontainer/readout as Label)
@onready var physicsprocessnetupdateoffsetreadout: Label = ($containercontainer/container/physicsprocessnetupdateoffsetdiffcontainer/readout as Label)
@onready var quackfpsreadout: Label = ($containercontainer/container/quackfpscontainer/readout as Label)
@onready var framedelayreadout: Label = ($containercontainer/container/framedelaycontainer/readout as Label)
@onready var timebehindserverreadout: Label = ($containercontainer/container/timebehindservercontainer/readout as Label)
@onready var netinputdelayreadout: Label = ($containercontainer/container/netinputdelaycontainer/readout as Label)
@onready var serverbufferreadout: Label = ($containercontainer/container/serverbuffercontainer/readout as Label)
@onready var totalinputdelayreadout: Label = ($containercontainer/container/totalinputdelaycontainer/readout as Label)
@onready var advancedfpsreadout: Label = ($containercontainer/container/advancedfpscontainer/readout as Label)
@onready var cpurenderreadout: Label = ($containercontainer/container/cpurendercontainer/readout as Label)
@onready var gpurenderreadout: Label = ($containercontainer/container/gpurendercontainer/readout as Label)
@onready var framesetupreadout: Label = ($containercontainer/container/framesetupcontainer/readout as Label)
@onready var renderfpsreadout: Label = ($containercontainer/container/renderfpscontainer/readout as Label)
@onready var processtimedeferredreadout: Label = ($containercontainer/container/processtimedeferredcontainer/readout as Label)
@onready var physicstimedeferredreadout: Label = ($containercontainer/container/physicstimedeferredcontainer/readout as Label)
@onready var processtimeidlereadout: Label = ($containercontainer/container/processtimeidlecontainer/readout as Label)
@onready var physicstimeidlereadout: Label = ($containercontainer/container/physicstimeidlecontainer/readout as Label)
@onready var rendertimereadout: Label = ($containercontainer/container/rendertimecontainer/readout as Label)
@onready var enetpacketlossreadout: Label = ($containercontainer/container/enetpacketlosscontainer/readout as Label)
@onready var enetpacketlossvariancereadout: Label = ($containercontainer/container/enetpacketlossvariancecontainer/readout as Label)
@onready var enetrttreadout: Label = ($containercontainer/container/enetrttcontainer/readout as Label)
@onready var enetjitterreadout: Label = ($containercontainer/container/enetjittercontainer/readout as Label)
@onready var enetlastrttreadout: Label = ($containercontainer/container/enetlastrttcontainer/readout as Label)
@onready var enetlastjitterreadout: Label = ($containercontainer/container/enetlastjittercontainer/readout as Label)
@onready var enetepochintervalreadout: Label = ($containercontainer/container/enetepochintervalcontainer/readout as Label)
@onready var netupdatejitterreadout: Label = ($containercontainer/container/netupdatejittercontainer/readout as Label)
@onready var estimatedcputimereadout: Label = ($containercontainer/container/estimatedcputimecontainer/readout as Label)
@onready var activethreadsreadout: Label = ($containercontainer/container/activethreadscontainer/readout as Label)
@onready var serverframereadout: Label = ($containercontainer/container/serverframecontainer/readout as Label)
@onready var mostrecentackedframereadout: Label = ($containercontainer/container/mostrecentackedframecontainer/readout as Label)
@onready var inputsignaturereadout: Label = ($containercontainer/container/inputsignaturecontainer/readout as Label)
@onready var ackedinputsignaturereadout: Label = ($containercontainer/container/ackedinputsignaturecontainer/readout as Label)
@onready var serverinputsignaturereadout: Label = ($containercontainer/container/serverinputsignaturecontainer/readout as Label)
@onready var inputbufferoffsetreadout: Label = ($containercontainer/container/inputbufferoffsetcontainer/readout as Label)
@onready var updownsreadout: Label = ($containercontainer/container/updownscontainer/readout as Label)
#@onready var test: Label = $containercontainer/container/test/label

@onready var gpuboundnoti: Label = ($containercontainer/gpuboundnoti as Label)
@onready var cpuboundnoti: Label = ($containercontainer/cpuboundnoti as Label)
@onready var processboundnoti: Label = ($containercontainer/processboundnoti as Label)
@onready var physicsboundnoti: Label = ($containercontainer/physicsboundnoti as Label)
@onready var physprocessboundnoti: Label = ($containercontainer/physprocessboundnoti as Label)
@onready var processphysboundnoti: Label = ($containercontainer/processphysboundnoti as Label)
@onready var inconsistentphysicsnoti: Label = ($containercontainer/inconsistentphysicsnoti as Label)
@onready var bigserverbuffernoti: Label = ($containercontainer/bigserverbuffernoti as Label)

@onready var client_readouts: Array[Label] = [
	framedelayreadout,
	timebehindserverreadout,
	netinputdelayreadout,
	serverbufferreadout,
	totalinputdelayreadout,
	enetpacketlossreadout,
	enetpacketlossvariancereadout,
	enetrttreadout,
	enetjitterreadout,
	enetlastrttreadout,
	enetlastjitterreadout,
	enetepochintervalreadout,
]

var processtime: float
var physprocesstime: float
var frame_hist: PackedInt64Array

# this needs to run exactly one time in a frame for accurate results
func get_num_frames() -> int:
	var num_frames: int = 0
	var has_empty_frame: bool
	var frame_offset: int
	for i in frame_hist.size():
		if TimeUtils.process_time_usec - frame_hist[i] >= TimeUtils.usec_in_seconds:
			frame_hist[i] = 0
			if !has_empty_frame:
				frame_offset = i
				has_empty_frame = true
		else:
			num_frames += 1
	if !has_empty_frame:
		frame_hist.append(TimeUtils.process_time_usec)
	else:
		frame_hist[frame_offset] = TimeUtils.process_time_usec
	return num_frames

static func to_ms(seconds: float) -> String:
	return to_msstring(TimeUtils.seconds_to_msecf(seconds))

static func to_msstring(ms: float) -> String:
	return str(snappedf(ms,.01)).left(4)+msstring

func _process(delta: float) -> void:
	fpsreadout.set_text(str(int(Engine.get_frames_per_second())))
	var cpu_time: float = 0
	for rid in measured_rids:
		cpu_time += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var gpu_time: float = 0
	for rid in measured_rids:
		gpu_time += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var cpu_setup_time: float = RenderingServer.get_frame_setup_time_cpu()
	var frametime: float = gpu_time + cpu_time + cpu_setup_time
	# get_num_frames() needs to be run exactly one time per frame
	advancedfpsreadout.set_text( str( get_num_frames() ) )
	renderfpsreadout.set_text( str( int(1000.0 / frametime) ) )
	rendertimereadout.set_text(to_msstring(frametime))
	@warning_ignore("static_called_on_instance")
	cpurenderreadout.set_text(to_msstring(cpu_time))
	@warning_ignore("static_called_on_instance")
	gpurenderreadout.set_text(to_msstring(gpu_time))
	@warning_ignore("static_called_on_instance")
	framesetupreadout.set_text(to_msstring(cpu_setup_time))
	quackfpsreadout.set_text(str(int(1.0/delta)))
	interpreadout.set_text(str(TimeUtils.interpfrac))
	interpbarreadout.set_value_no_signal(TimeUtils.interpfrac)
	@warning_ignore("static_called_on_instance")
	deltareadout.set_text(to_ms(delta))
	processtime = Performance.get_monitor(Performance.TIME_PROCESS)
	@warning_ignore("static_called_on_instance")
	processtimereadout.set_text(to_ms(processtime))
	@warning_ignore("static_called_on_instance")
	quackdeltareadout.set_text(to_ms(TimeUtils.process_delta_time_float))
	processdeltatimediffreadout.set_text(str(delta - processtime))
	processquackdeltadiffreadout.set_text(str(delta - TimeUtils.process_delta_time_float))
	var netupdaterate: float = TimeUtils.usec_to_seconds(Network.delta_time_net_receive)
	netupdateratereadout.set_text(to_ms(netupdaterate))
	netupdatejitterreadout.set_text(to_ms(TimeUtils.usec_to_seconds(Network.last_jitter)))
	physicsnetdiffreadout.set_text(str(netupdaterate - physicsprocessrate))
	var netupdateoffset: float = TimeUtils.usec_get_sec_offset_from_second(Network.current_time_net_receive)
	netupdateoffsetreadout.set_text(str(netupdateoffset))
	physicsprocessnetupdateoffsetreadout.set_text(str(netupdateoffset-physicsprocessoffset))
	var frametimesec := TimeUtils.msecf_to_seconds(frametime)
	var estimated_cpu_time := processtime - frametimesec
	estimatedcputimereadout.set_text(to_ms(estimated_cpu_time))
	var gpu_bound: bool = estimated_cpu_time < frametimesec
	var scaled_delta: float = delta / Engine.time_scale
	activethreadsreadout.set_text(str(Quack.ThreadUtils.threads.size()))
	update_process_time_deferred.call_deferred()
	update_noti_visibility(gpuboundnoti,gpu_bound)
	update_noti_visibility(cpuboundnoti,!gpu_bound)
	update_noti_visibility(processboundnoti,processtime > scaled_delta)
	update_noti_visibility(physprocessboundnoti, processtime + physprocesstime > scaled_delta)

func update_process_time_deferred() -> void:
	processtimedeferredreadout.set_text(to_ms(TimeUtils.usec_to_seconds(TimeUtils.deferred_process_time_usec - TimeUtils.process_time_usec)))
	update_process_time_idle.call_deferred()

func update_process_time_idle() -> void:
	processtimeidlereadout.set_text(to_ms(TimeUtils.usec_to_seconds(TimeUtils.idle_process_time_usec - TimeUtils.process_time_usec)))

func update_physics_time_deferred() -> void:
	physicstimedeferredreadout.set_text(to_ms(TimeUtils.usec_to_seconds(TimeUtils.deferred_physics_time_usec - TimeUtils.physics_time_usec)))
	update_physics_time_idle.call_deferred()

func update_physics_time_idle() -> void:
	physicstimeidlereadout.set_text(to_ms(TimeUtils.usec_to_seconds(TimeUtils.idle_physics_time_usec - TimeUtils.physics_time_usec)))

var physicsprocessrate: float
var physicsprocessoffset: float
func _physics_process(delta: float) -> void:
	physprocesstime = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	@warning_ignore("static_called_on_instance")
	physdeltareadout.set_text(to_ms(delta))
	@warning_ignore("static_called_on_instance")
	quackphysdeltareadout.set_text(to_ms(Tickrate.physics_delta))
	@warning_ignore("static_called_on_instance")
	physprocesstimereadout.set_text(to_ms(physprocesstime))
	physicsprocesstimedeltadiffreadout.set_text(str(delta - physprocesstime))
	physicsprocessrate = TimeUtils.usec_to_seconds(TimeUtils.physics_delta_time_usec)
	@warning_ignore("static_called_on_instance")
	physicsprocessratereadout.set_text(to_ms(physicsprocessrate))
#	(Quack.current_time_physics-Quack.physics_start_time)%1000000
	physicsprocessoffset = TimeUtils.usec_get_sec_offset_from_second(TimeUtils.physics_time_usec)
	physicsprocessoffsetreadout.set_text(str(physicsprocessoffset))
	update_physics_time_deferred.call_deferred()
	if Network.is_client():
		update_network_readouts()
	# //////// Stupid debug stuff
		if client:
			serverframereadout.set_text(str(client.most_recent_acked_frame.num))
	if client:
		serverframereadout.set_text(str(Network.MultiplayerSession.frame_num))
		update_client_debug_readouts()
	# //////// Stupid debug stuff ^^&&
	var scaled_delta: float = delta / Engine.time_scale
	update_noti_visibility(physicsboundnoti,physprocesstime > scaled_delta)
	# might be an issue if timescale set to 0
	update_noti_visibility(inconsistentphysicsnoti,absf(physicsprocessrate - scaled_delta) / scaled_delta > INCONSISTENT_THRESHOLD)
	update_noti_visibility(processphysboundnoti, processtime + physprocesstime > scaled_delta)
const INCONSISTENT_THRESHOLD = .1

const framestring = "f"
const msstring = "ms"

func update_network_readouts() -> void:
	var local_client := Network.MultiplayerSession.local_client
	if !local_client:
		return
	var frame_delay := local_client.get_frame_delay()
	framedelayreadout.set_text(str(frame_delay)+framestring)
	timebehindserverreadout.set_text(str(TimeUtils.frames_to_ms(frame_delay))+msstring)
	#var net_input_delay: int = local_client.get_network_input_delay()
	netinputdelayreadout.set_text(str(TimeUtils.frames_to_ms(local_client.get_network_input_delay()))+msstring)
	#var server_input_buffer_size: int = local_client.get_server_input_buffer_size()
	serverbufferreadout.set_text(str(local_client.get_server_input_buffer_size())+framestring)
	totalinputdelayreadout.set_text(str(TimeUtils.frames_to_ms(local_client.get_total_input_delay()))+msstring)
	if packet_peer and packet_peer.is_active():
		var enetpacketloss := get_enet_packet_loss(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS))
		# kinda dumb to do this in perf overlay but fuck it lmao, also this doesnt
		# seem to even do anything, even if ping() is called manually
		if enetpacketloss > .01:
			packet_peer.ping_interval(200)
		else:
			packet_peer.ping_interval(500)
		enetpacketlossreadout.set_text(str(enetpacketloss)+"%")
		enetpacketlossvariancereadout.set_text(str(get_enet_packet_loss(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS_VARIANCE)))+"%")
		enetrttreadout.set_text(to_msstring(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)))
		enetjitterreadout.set_text(to_msstring(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)))
		enetlastrttreadout.set_text(to_msstring(packet_peer.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME)))
		enetlastjitterreadout.set_text(to_msstring(packet_peer.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME_VARIANCE)))
		var epoch := packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS_EPOCH)
		if epoch != last_epoch:
			enetepochintervalreadout.set_text(to_msstring(epoch-last_epoch))
			last_epoch = epoch

func update_client_debug_readouts() -> void:
	mostrecentackedframereadout.set_text(str(client.most_recent_acked_frame.num))
	inputsignaturereadout.set_text(str(client.input_signature))
	ackedinputsignaturereadout.set_text(str(client.acked_input_signature))
	serverinputsignaturereadout.set_text(str(client.server_input_signature))
	inputbufferoffsetreadout.set_text(str(client.input_buffer_offset))
	if client.players.size() > 0:
		var input := client.players[0].get_input()
		updownsreadout.set_text(str(input.updowns))
	
	@warning_ignore("integer_division")
	update_noti_visibility(bigserverbuffernoti,false)#server_input_buffer_size - net_input_delay > net_input_delay / 2)

static func get_enet_packet_loss(loss: float) -> float:
	return snappedf((loss / ENetPacketPeer.PACKET_LOSS_SCALE) * 100,.01)

func call_all(callables: Array[Callable]) -> void:
	for callable in callables:
		callable.call()

func update_noti_visibility(noti: Label, visibility: bool) -> void:
	noti.visible_characters = -1 if visibility else 0
