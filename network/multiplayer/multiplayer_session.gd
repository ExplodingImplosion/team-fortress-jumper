const Client = preload("res://network/multiplayer/client.gd")
const QuackPlayer = preload("res://network/multiplayer/player.gd")
const Network = preload("res://network/network.gd")
const MultiplayerSession = preload("res://network/multiplayer/multiplayer_session.gd")
const QuackMultiplayer = Network.QuackMultiplayer
const HistorySaver = preload("res://gameplay/level/common/multiplayer_level.gd").HistorySaver
const ThreadUtils = preload("res://utils/thread_utils.gd")

static var clients: Dictionary[int,Client]
static var players: Dictionary[int,QuackPlayer]
static var local_client: Client

static var max_players: int
static var max_spectators: int

class Emitter:
	signal client_added(client: Client)
	signal player_added(player: QuackPlayer)
	signal client_readied(client: Client)
	signal player_readied(player: QuackPlayer)
	signal client_removed(client: Client)
	signal player_removed(player: QuackPlayer)

static var emitter := Emitter.new()
static var client_added: Signal = emitter.client_added
static var player_added: Signal = emitter.player_added
static var client_readied: Signal = emitter.client_readied
static var player_readied: Signal = emitter.player_readied
static var client_removed: Signal = emitter.client_removed
static var player_removed: Signal = emitter.player_removed

static func send_states_to_clients(history: HistorySaver) -> void:
	frame_num += 1
	var most_recent_frame := history.get_recent_frame()
	if !most_recent_frame: return # This happens on first frame in a localhost situation
	for client_id in get_ready_clients():
		var client := clients[client_id]
		if Network.threaded_encoding:
			ThreadUtils.add_locked_thread(client,client.send_delta_packet.bind(most_recent_frame),true)
			#ThreadUtils.add_thread(clients[client_id].send_delta_packet.bind(most_recent_frame),true)
		else:
			ThreadUtils.cleanup_locked_thread(client)
			client.send_delta_packet(most_recent_frame)

static func reset() -> void:
	for client in clients.values():
		(client as Client).clear()
	clients.clear()
	players.clear()
	ready_clients.clear()
	ready_clients_cache_valid = false
	frame_num = 0
	max_players = 0
	max_spectators = 0
	predicting = false

static var frame_num: int = 0
static var ready_clients: PackedInt32Array
static var ready_clients_cache_valid: bool = false
static var predicting: bool = false

static func client_is_ready(id: int) -> bool:
	return clients[id].ready

static func add_client(id: int, num_players: int = 1) -> Client:
	assert(not clients.has(id),"Client list already has id %s."%id)
	var client := Client.new(id,num_players)
	clients[id] = client
	return client

static func add_local_client(id: int, num_players: int = 1) -> Client:
	var client := add_client(id,num_players)
	local_client = client
	return client

static func add_dummy_client(id: int) -> Client:
	return add_client(id,0)

static func mark_client_ready(id: int) -> void:
	clients[id].mark_ready()
	ready_clients.append(id)

static func remove_client(id: int) -> void:
	var client := clients[id]
	client.clear()
	# Should probably go after, but this retains parity with how player removed
	# signals are emitted where they're emitted before theyre cleared from clients
	client_removed.emit(client)
	clients.erase(id)
	ready_clients_cache_valid = false

static func get_ready_clients() -> PackedInt32Array:
	if ready_clients_cache_valid: return ready_clients
	ready_clients.resize(clients.size())
	var count: int = 0
	for id in clients:
		if clients[id].ready:
			ready_clients[count] = id
			count += 1
	ready_clients.resize(count)
	ready_clients_cache_valid = true
	return ready_clients

static func are_clients_friendly(cid1: int, cid2: int) -> bool:
	return clients[cid1].is_friendly_to(clients[cid2])

static func tick(history_saver: HistorySaver) -> void:
	
	local_client.tick_player_inputs()
	
	if Network.is_client():
		local_client.tick_local()
	else:
		for client:Client in MultiplayerSession.clients.values():
			if client.id <= 1: continue
			if client.input_signature < client.acked_input_signature:
				client.tick_input_buffer()
				#if Input.is_action_pressed("ui_accept"):
					#Console.write(
						#"%s | Was pressed: %s | Input sig: %s | Input offset: %s | Server sig: %s | Server used sig: %s | Most recent acked frame: %s [%s]"%[
							#Engine.get_physics_frames(),client.players[0].get_input().is_action_just_pressed(&"jump"), client.input_signature,client.input_buffer_offset,client.acked_input_signature,client.server_input_signature,client.most_recent_acked_frame.num,MultiplayerSession.frame_num
						#]
					#)
		if Network.multiplayer_connected():
			send_states_to_clients(history_saver)
