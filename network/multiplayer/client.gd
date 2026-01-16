const Client = preload("res://network/multiplayer/client.gd")
const QuackPlayer = preload("res://network/multiplayer/player.gd")
const MultiplayerLevel = preload("res://gameplay/level/common/multiplayer_level.gd")
const Frame = MultiplayerLevel.RecentFrame
const Replay = MultiplayerLevel.Replay
const Teams = preload("res://gameplay/team_component.gd")
const OwnerID = preload("res://gameplay/owner_id.gd")
const Network = NetworkPacket.Network
const NetworkPacket = preload("res://network/packets/packet.gd")
const WorldStatePacket = NetworkPacket.WorldStatePacket
const ReadyPacket = NetworkPacket.ClientReadyPacket
const InfoPacket = NetworkPacket.ClientInfoPacket
const PacketSender = NetworkPacket.PacketType
const InputPacket = NetworkPacket.InputPacket
const WorldStateConfirmationPacket = NetworkPacket.WorldStateConfirmationPacket
const MultiplayerSession = Network.MultiplayerSession

var id: int
var players: Array[QuackPlayer]
var ready: bool
var most_recent_acked_frame: Frame = Frame.new([],0)
var dirty_frame: Frame = Frame.new([],0)
var server_acked_frame_num: int
var team: int
var most_recent_received_frame: WorldStatePacket
var input_signature: int
var acked_input_signature: int
var server_input_signature: int
var input_buffer_offset: int = -1 # Idk why but maybe this might actually be useful to have at 1
var replay: Replay
var fucked: bool = false

func _to_string() -> String:
	return "%s client %s, [%s players, most recent acked frame %s, server acked frame %s, hostility mask %s]"%[
		"Ready" if ready else "Unready",id,players.size(),most_recent_acked_frame.num,server_acked_frame_num,team
	]

func mark_ready() -> void:
	if ready == true:
		return Console.push_err("Client %s marked ready while already ready."%id)
	ready = true
	for player in players:
		MultiplayerSession.player_readied.emit(player)
	MultiplayerSession.client_readied.emit(self)

func get_player(player_id: int) -> QuackPlayer:
	return players[player_id - id]

func get_team_mask() -> int:
	var mask: int = 0
	for player in players:
		mask |= player.team
	return mask

func _init(unique_id: int, num_players: int) -> void:
	id = unique_id
	players.resize(num_players)
	for i in num_players:
		var player := QuackPlayer.new(self,i)
		players[i] = player
		MultiplayerSession.players[player.id] = player
	if (Network.is_server() and Network.store_send_replays) or Network.store_receive_replays:
		replay = Replay.new(Quack.get_current_scene(),Quack.Tickrate.target_physics_rate,id)
	MultiplayerSession.client_added.emit(self)

var uid_map: Dictionary[int,int] # UIDs, frames

var max_command_frame_rate: int = 0
var buffer_time: float = 0.
var input_buffer_time: float = 0.
var server_input_buffer_time: float = 0.

var max_receive_bandwidth: int = 0
var max_send_bandwidth: int = 0

func clear() -> void:
	Quack.ThreadUtils.cleanup_locked_thread(self,true)
	save_local_replay()
	for node in get_local_nodes():
		node.queue_free()
	for player in players:
		MultiplayerSession.player_removed.emit(player)
	players.clear()

func add_player() -> void:
	var player := QuackPlayer.new(self,players.size())
	players.append(player)
	MultiplayerSession.players[player.id] = player

func get_local_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for player in players:
		nodes.append_array(OwnerID.get_nodes_owned_by(player.id))
	return nodes

func save_local_replay() -> void:
	if replay and replay.size > 0:
		replay.save("Client %s %s replay %s"%[id,"receive" if self == MultiplayerLevel.MultiplayerSession.local_client else "send",hash(replay.buffer.data_array)])

func is_friendly_to(client: Client) -> bool:
	return Teams.teams_are_friendly(team,client.team)

func send_delta_packet(frame: Frame) -> void:
	
	dirty_frame.merge(frame) # Dirty frame now has most up to date info
	var delta := dirty_frame.get_delta(most_recent_acked_frame,id,team)
	
	add_packet_to_replay(delta)
	
	PacketSender.send_packet_to_client(
		id,
		WorldStatePacket.create(
			frame.num,
			most_recent_acked_frame.num,
			delta,
			input_signature,
			acked_input_signature
		)
	)

func receive_worldstate(packet: WorldStatePacket) -> void:
	server_acked_frame_num = packet.u32_last_frame
	# Maybe if older frames should be stored somehow, then change how assignment
	# works to some kind of array or dictionary
	most_recent_received_frame = packet
	add_packet_to_replay(packet.contents)

func add_packet_to_replay(packet: PackedByteArray) -> void:
	if replay:
		#Network.encode_threaded(replay.append_frame.bind(delta))
		if Network.threaded_encoding:
			Quack.ThreadUtils.add_thread(replay.append_frame.bind(packet))
		else:
			replay.append_frame(packet)

func decode_worldstate(packet: WorldStatePacket) -> void:
	most_recent_acked_frame.decode_delta(packet.contents,id,packet.u32_frame,packet.u32_last_frame)

func notify_ready() -> void:
	PacketSender.send_packet_to_server(ReadyPacket.new())

func send_info() -> void:
	PacketSender.send_packet_to_server(InfoPacket.create(self))

func set_info(max_cfr: int, buffer_length: float, input_buffer_length: float, server_input_buffer_length: float, max_in_bandwith: int, max_out_bandwidth: int) -> void:
	max_command_frame_rate = Network.clamp_allow_0(max_cfr, Network.MIN_COMMAND_FRAMERATE, Network.MAX_COMMAND_FRAMERATE)
	buffer_time = clampf(buffer_length,0.,Network.MAX_BUFFER_LENGTH)
	input_buffer_time = clampf(input_buffer_length,0.,Network.MAX_INPUT_BUFFER_LENGTH)
	server_input_buffer_time = clampf(server_input_buffer_length,0.,Network.MAX_SERVER_INPUT_BUFFER_LENGTH)
	max_receive_bandwidth = Network.clamp_allow_0(max_in_bandwith, Network.MIN_BANDWIDTH, Network.MAX_BANDWIDTH)
	max_send_bandwidth = Network.clamp_allow_0(max_out_bandwidth, Network.MIN_BANDWIDTH, Network.MAX_BANDWIDTH)

func send_input() -> void:
	InputPacket.send()

func get_frame_delay() -> int:
	return most_recent_acked_frame.num - server_acked_frame_num

## How many inputs the server hasn't received yet
func get_network_input_delay() -> int:
	return input_signature - acked_input_signature

## How many inputs the server has received, but hasn't processed yet
func get_server_input_buffer_size() -> int:
	return acked_input_signature - server_input_signature

## How many inputs ahead this client is from the server.
func get_total_input_delay() -> int:
	return input_signature - server_input_signature

#nput_delay: int = local_client.input_signature - local_client.acked_input_signature
	#netinputdelayreadout.set_text(str(TimeUtils.frames_to_ms(net_input_delay))+msstring)
	#var server_input_buffer_size: int = local_client.acked_input_signature - local_client.server_input_signature
	#serverbufferreadout.set_text(str(server_input_buffer_size)+framestring)
	#totalinputdelayreado

func update_locally_owned_nodes(nodes := get_local_nodes()) -> void:
	for node in nodes:
		if MultiplayerLevel.Serializer.component_list.has(node):
			var serializer := MultiplayerLevel.Serializer.component_list[node]
			if serializer.updating:
				# Calling receive_instant_update resets physics interp and would
				# cause a pop... maybe? this happens within the physics frame
				# so maybe it wouldnt. idk change at your discretion
				serializer.receive_update(serializer.serialized.property_lists)
				if serializer.update_frequency == 0.:
					serializer.updating = false
				else:
					serializer.update_time_left += Quack.Tickrate.physics_delta
					if serializer.update_time_left >= serializer.update_frequency:
						serializer.updating = false
						serializer.update_time_left = 0.

func predict() -> void:
	MultiplayerSession.predicting = true
	#var frame_delay := get_frame_delay()
	var nodes := get_local_nodes()
	
	update_locally_owned_nodes(nodes)
	
	#var offset := input_buffer_offset
	var input_delay: int = clampi(get_total_input_delay(),0,120)
	change_input_buffer_offset(-input_delay)
	#Console.write("Offset %s --> %s, input sig %s == %s?"%[offset,input_buffer_offset,acked_input_signature,input_signature-get_total_input_delay()])
	for i in input_delay:
		#Console.write("simulating sig %s at offset %s"%[
			#acked_input_signature+i,input_buffer_offset
		#])
		for node in nodes:
			if MultiplayerLevel.Serializer.component_list.has(node):
				var serializer := MultiplayerLevel.Serializer.component_list[node]
				# Because of how frame_created gets set, this is gonna be at
				# least off by 1 but im too lazy to fix it. BUG BUG BUG BUG BUG
				if serializer.serialized.frame_created <= MultiplayerSession.frame_num - input_delay + i:
					# Maybe change how this works. Because for whatever fucking reason,
					# calling propagate_notification makes it propagate to all child nodes,
					# even if they're disabled! So every individual node that needs to be
					# allowed to disable needs to manually account for this! Fuck!
					if node.process_mode != Node.PROCESS_MODE_DISABLED:
						node.propagate_notification(Node.NOTIFICATION_PHYSICS_PROCESS)
		change_input_buffer_offset()
	#assert(input_buffer_offset == offset, "%s %s"%[input_buffer_offset,offset])
	#input_buffer_offset = offset
	MultiplayerSession.predicting = false

func tick_input_buffer() -> void:
	input_signature += 1
	set_input_buffer_offset(input_signature)

func change_input_buffer_offset(amnt: int = 1) -> void:
	input_buffer_offset = wrapi(input_buffer_offset+amnt,0,Network.input_buffer_size)

func set_input_buffer_offset(position: int) -> void:
	input_buffer_offset = wrapi(position,0,Network.input_buffer_size)

func tick_player_inputs() -> void:
	tick_input_buffer()
	for player in players:
		# This is a stupid hack to ensure that there arent arbitrary firing
		# interp fracs on frames when weapons are refired/fired from automatic
		# Ideally, firing interp frac would only be set when weapons fire and
		# when players press inputs, but because weapon logic happens after inputs
		# are collected / sent, it needs to happen here.
		player.get_input(1).firing_interp_fraction = 0.
		player.apply_local_inputs()

func tick_local() -> void:
	
	if fucked:
		return Console.writerr("client is fucked")
	
	if not players.is_empty():
		send_input()
	if most_recent_received_frame:
		WorldStateConfirmationPacket.send(most_recent_received_frame.u32_frame)
		#if WorldStatePacket.num_received >= 2:
			#breakpoint
		server_input_signature = most_recent_received_frame.u32_input_signature
		acked_input_signature = most_recent_received_frame.u32_acked_signature
		decode_worldstate(most_recent_received_frame)
		MultiplayerSession.frame_num = most_recent_acked_frame.num
		most_recent_received_frame = null
		predict()
	
	Network.Tickrate.adjust_for_buffer_size(get_server_input_buffer_size())
	
