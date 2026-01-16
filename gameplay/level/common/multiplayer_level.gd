extends Node3D

const Serializer = preload("res://gameplay/serializer.gd")
const QuackMultiplayer = preload("res://network/multiplayer/quack_multiplayer.gd")
const MultiplayerLevel = preload("res://gameplay/level/common/multiplayer_level.gd")
const StreamPeerBitBuffer = preload("res://utils/stream_peer_bit_buffer.gd")
const PhysicsPriority = preload("res://utils/process_priorities.gd").Physics.Priorities
const NetworkPacket = preload("res://network/packets/packet.gd")
const MultiplayerSession = preload("res://network/multiplayer/multiplayer_session.gd")
const Network = MultiplayerSession.Network
const ThreadUtils = preload("res://utils/thread_utils.gd")
const Replay = preload("res://network/multiplayer/replays.gd")
const SerializedNodeCollection = Serializer.SerializedNodeCollection
const BoundingBox = preload("res://gameplay/network_bounding_box_component.gd")
const RecentFrame = preload("res://network/multiplayer/recent_frame.gd")
const HitResolver = preload("res://network/multiplayer/hit_resolver.gd")

var history_saver: HistorySaver

func _init() -> void:
	Serializer.component_tracker.component_added.connect(on_node_spawned)
	Serializer.component_tracker.component_removed.connect(on_node_deleted)#,CONNECT_DEFERRED)
	# Maybe deferring is undesired if behavior depends on nodes being spawned midway thru the frame idk
	if Network.is_server():
		
		# Maybe get rid of this later for local replay stuff
		if Network.is_in_multiplayer():
			history_saver = HistorySaver.new(self)
			add_child(HitResolver.new(self))
			add_child(history_saver)
		
			#child_entered_tree.connect(on_node_spawned_auth,CONNECT_DEFERRED)
			#child_exiting_tree.connect(on_node_deleted_auth,CONNECT_DEFERRED)
			Quack.Network.get_mp().peer_disconnected.connect(remove_client)
			MultiplayerSession.add_local_client(1,Quack.num_users)
			# HACK cuz rn needs client for session to check teams NOTE maybe dont need anymore
			MultiplayerSession.add_dummy_client(0)
	else:
		pass
	if Quack.num_users > 1: Quack.Splitscreen.start_splitscreen()

func _physics_process(_delta: float) -> void:
	# Poll BEFORE processing inputs and state. Server gets new inputs, clients
	# get new server state.
	Console.write_if_error(multiplayer.poll())
	# Tick multiplayer session. This is where inputs are ticked forward for clients
	# both locally and on the server, and states are sent to ready clients. Local
	# clients perform prediction.
	MultiplayerSession.tick(history_saver)
	# Poll AFTER processing inputs and state. Packets aren't sent until multiplayer
	# polls again, it's done here as well. This sends new inputs to the server
	# and new states to clients. Although a client or server could receive a late
	# state or input respectively, this won't (or at least shouldnt) fuck things
	# up, because new states and inputs are only important during MultiplayerSession's
	# tick.
	Console.write_if_error(multiplayer.poll())
	if Network.NetDebug.lag_faker_active():
		Network.NetDebug.lag_faker.process_packets()

func _ready() -> void:
	if not Network.is_server():
		for node in Serializer.component_list.keys():
			Console.writeverb("Freeing networked node %s"%node.name)
			node.queue_free()
			# For some reason owner.tree_exited.connect(on_owner_exit_tree)
			# doesn't get propertly hooked up by the time that the objects
			# are freed, so this is here lmao
			Serializer.component_list.erase(node)
		
		if Network.is_in_multiplayer():
			MultiplayerSession.local_client.notify_ready()

func remove_client(id: int) -> void:
	for node in OwnerID.get_nodes_owned_by(id):
		node.queue_free()

const ConsoleCommands = Console.console_commands_script
const OwnerID = ConsoleCommands.OwnerID
const Team = MultiplayerSession.Client.Teams
func on_notified_ready(id: int) -> void:
	if not MultiplayerSession.client_is_ready(id):
		Console.write("Client %s notified ready."%id)
		ConsoleCommands.spawn_dummy_cmd()
		OwnerID.add_node_owner(Quack.tree.get_nodes_in_group(&"Player")[-1],id)

func on_node_spawned(serializer: Serializer) -> void:
	serializer.increment_uid()
	Console.writeverb("Node %s is serialized. Spawning %s [%s] remotely."%[
		serializer.owner.name,serializer.owner.scene_file_path,QuackMultiplayer.scene_registry[serializer.owner.scene_file_path]
	])

func on_node_deleted(serializer: Serializer) -> void:
	# Because owner is cleared seemingly "early" when nodes are deleted, im just
	# hacking it to do the first serialized node lmao
	Console.writeverb("Node %s is serialized. Deleting node."%serializer.nodes[0].name)

func _exit_tree() -> void:
	Quack.Splitscreen.cleanup_splitscreen()
	if not Quack.Network.multiplayer_connected():
		MultiplayerSession.reset()
	if not (Network.is_server() and Quack.Network.multiplayer_connected()): return
	for serializer in Serializer.get_serializers():
		on_node_deleted(serializer as Serializer)

class HistorySaver extends Node:
	
	var recent_frames: Array[RecentFrame]
	var history: Replay
	var level: MultiplayerLevel
	var recent_frame_idx: int = 0
	
	func _init(mp_level: MultiplayerLevel) -> void:
		process_physics_priority = PhysicsPriority.HISTORY_SAVER
		level = mp_level
		recent_frames.resize(256)
		recent_frames.fill(RecentFrame.new([],0))
		setup_replay.call_deferred()
	
	func _exit_tree() -> void:
		ThreadUtils.cleanup_locked_thread(self,true)
		ThreadUtils.add_thread(history.save)
	
	func setup_replay() -> void:
		history = Replay.new(level,Quack.Tickrate.target_physics_rate)
		
	func _physics_process(_delta: float) -> void:
		if Quack.is_multiplayer_authority():
			serialize_frame.call_deferred()
	
	func serialize_frame() -> void:
		var serializations: Array[SerializedNodeCollection]
		for serializer in Serializer.get_serializers():
			# Do this even if serializer isn't updating
			if not serializer.has_serialized:
				serializer.serialize_nodes()
			serializations.append(serializer.serialized.duplicate())
		add_recent_frame(RecentFrame.new(serializations))
		if Network.threaded_encoding:
			ThreadUtils.add_locked_thread(self,add_current_frame_to_history,true)
		else:
			ThreadUtils.cleanup_locked_thread(self)
			add_current_frame_to_history()
	
	func add_current_frame_to_history() -> void:
		history.append_frame(get_recent_frame().get_delta(get_recent_frame(1) if history.size > 1 else RecentFrame.new([])))
	
	func get_recent_frame(offset: int = 0) -> RecentFrame:
		return recent_frames[wrapi(recent_frame_idx-(offset+1),0,256)]
	
	func get_frame(frame_num: int) -> RecentFrame:
		assert(get_recent_frame(get_recent_frame().num - frame_num).num == frame_num,"%s != %s"%[get_recent_frame(get_recent_frame().num - frame_num).num,frame_num])
		return get_recent_frame(get_recent_frame().num - frame_num)
	
	func get_frame_clamped(frame_num: int) -> RecentFrame:
		return get_recent_frame(clampi(recent_frames[recent_frame_idx-1].num - frame_num,0,255))
	
	func add_recent_frame(frame: RecentFrame) -> void:
		recent_frames[recent_frame_idx] = frame
		recent_frame_idx = wrapi(recent_frame_idx+1,0,256)
