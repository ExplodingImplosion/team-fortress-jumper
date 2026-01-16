#region Script consts
const ServerBrowser = preload("res://network/server_browser.gd")
const QuackMultiplayer = preload("res://network/multiplayer/quack_multiplayer.gd")
const Tickrate = Quack.Tickrate
const WindowUtils = Quack.WindowUtils
const ConnectivityTester = preload("res://network/connectivity_tester.gd")
const NetDebug = preload("res://utils/network_debugger.gd")
const Serializer = preload("res://gameplay/serializer.gd")
const NetworkPackets = preload("res://network/packets/packet.gd")
const MultiplayerSession = preload("res://network/multiplayer/multiplayer_session.gd")
#endregion

enum {DISCONNECTED = -1, HOST, SERVER}
const localhost = 'localhost'
const loopback = '127.0.0.1'
enum {DEFAULT_PORT = 25565, DEFAULT_BROWSER_PORT = 42069, DEFAULT_LOCAL_BROWSER_PORT = 25566}

const NETWORK_SETTINGS_PATH = "quack/network/"
const CLIENT_SETTINGS_PATH = NETWORK_SETTINGS_PATH+"client/"
const HOST_SETTINGS_PATH = NETWORK_SETTINGS_PATH+"host/"
const CLIENT_PREFERENCES_SETTINGS_PATH = CLIENT_SETTINGS_PATH+"preferences/"
const MAXRECEIVE = "bandwidth/max_receive_bandwidth"
const MAXSEND = "bandwidth/max_send_bandwidth"
const MAXCMDFR = "maximum_command_frame_rate"

const CLIENT_COMMAND_FRAME_RATE_SETTING_PATH = CLIENT_SETTINGS_PATH+MAXCMDFR
const PREFERRED_BUFFER_SIZE_SETTING_PATH = CLIENT_PREFERENCES_SETTINGS_PATH+"buffer_time"
const PREFERRED_RECEIVE_RAT_SETTING_PATHE = CLIENT_PREFERENCES_SETTINGS_PATH+"receive_rate"
const PREFERRED_INPUT_BUFFER_LENGTH_SETTING_PATH = CLIENT_PREFERENCES_SETTINGS_PATH+"input_buffer_time"
const PREFERRED_SERVER_INPUT_BUFFER_TIME_SETTING_PATH = CLIENT_PREFERENCES_SETTINGS_PATH+"server_input_buffer_time"
const MAX_RECEIVE_CLIENT_SETTING_PATH = CLIENT_SETTINGS_PATH + MAXRECEIVE
const MAX_SEND_CLIENT_SETTING_PATH = CLIENT_SETTINGS_PATH + MAXSEND
const STORE_RECEIVE_REPLAYS_SETTING_PATH = CLIENT_SETTINGS_PATH + "store_receive_replays"

const HOST_COMMAND_FRAME_RATE_SETTING_PATH = HOST_SETTINGS_PATH+MAXCMDFR
const HOST_MIN_INPUT_BUFFER_LENGTH_SETTING_PATH = HOST_SETTINGS_PATH+"minimum_input_buffer_time"
const MINIMUM_LATENCY_SETTING_PATH = HOST_SETTINGS_PATH+"minimum_latency"
const MAX_RECEIVE_HOST_SETTING_PATH = HOST_SETTINGS_PATH + MAXRECEIVE
const MAX_SEND_HOST_SETTING_PATH = HOST_SETTINGS_PATH + MAXSEND
const STORE_SEND_REPLAYS_SETTING_PATH = HOST_SETTINGS_PATH +"store_send_replays"

const COMPRESSION_SETTING_PATH = NETWORK_SETTINGS_PATH+"compression"
const THREADED_ENCODING_SETTING_PATH = NETWORK_SETTINGS_PATH+"threaded_encoding"
const ONLINE_SETTING_PATH = NETWORK_SETTINGS_PATH+"online"

static var peer: ENetMultiplayerPeer = null
static var is_connected_to_internet: bool
static var pub_ipv4: String # Dangerous

const max_channels = 32
const channel_count = 0
const client_port_bound = false

static var input_buffer_size: int = Inputs.INPUT_BUFFER_SIZE
#static var worldstate_buffer_size: int
#static var packet_buffer_size: int

static var server_browser := ServerBrowser.new()

## Used in [method update_net_receive_time] to calculate the
## [member delta_time_net_receive] by updating to [method Time.get_ticks_usec],
## and subtracting [member last_time_net_receive] from this value.
static var current_time_net_receive: int = 0
## The last time, in usec, that a multiplayer packet was received.
static var last_time_net_receive: int = 0
## The difference, in usec, between the last time a multiplayer packet was
## received, and the most recent time a multiplayer packet was received.
static var delta_time_net_receive: int = 0
## Used to calculate the estimated times when a client should expect to receive
## multiplayer packets. Updated to [method Time.get_ticks_usec] when
## [method receive_server_info] is called.
static var net_receive_start_time: int = 0
static var last_jitter: int

static var jitter_hist: PackedInt32Array
static var jitter_offset: int = 0

## Updates [member current_time_net_receive], [member last_time_net_receive]
## and calculates [member delta_time_net_receive] by subtracting the former two.
## Called every time the game receives a multiplayer packet.
static func update_net_receive_time() -> void:
	current_time_net_receive = Time.get_ticks_usec()
	var prev_d := delta_time_net_receive
	delta_time_net_receive = current_time_net_receive - last_time_net_receive
	last_time_net_receive = current_time_net_receive
	last_jitter = absi(delta_time_net_receive - prev_d)
	jitter_hist[jitter_offset] = last_jitter
	jitter_offset = wrapi(jitter_offset+1,0,101)

static func get_highest_jitter() -> int:
	var sorted := jitter_hist.duplicate()
	sorted.sort()
	return sorted[-1]

static func begin_net_receive_tracking() -> void:
	net_receive_start_time = Time.get_ticks_usec()
	last_time_net_receive = net_receive_start_time

static func initialize() -> void:
	@warning_ignore("assert_always_true")
	#assert(NetworkPacket.PACKET_TYPE_MAX < 257, "Number of packet types must fit into a single u8, but PACKET_TYPE_MAX is currently %s, which implies there are 256 or more packet types."%[NetworkPacket.PACKET_TYPE_MAX])
	#QuackMultiplayer.register_all_scripts()
	QuackMultiplayer.register_scenes()
	#server_browser.begin_broadcasting_as_client.call_deferred()
	server_browser.begin_listening.call_deferred()
	NetworkPackets.PacketType.setup_packet_map()
	jitter_hist.resize(101)
	#Events.initialize_events()
	#ClientPacket.num_packet_types = ClientPacket.initialize_packet_types(ClientPacket,ClientPacket.packet_type_map,ClientPacket.packet_types)
	#ServerPacket.num_packet_types = ServerPacket.initialize_packet_types(ServerPacket,ServerPacket.packet_type_map,ServerPacket.packet_types)
	#assert(Events.event_map.size() == Events.event_types.size(),"Event map and event types must be of same size, but %s != %s."%[
		#Events.event_map.size(),Events.event_types.size()])
	#assert(Events.num_events < 257, "Number of events must fit into a single u8, but EVENTMAX is currently %s, which implies there are 256 or more events."%[Events.num_events])

static func get_mp() -> MultiplayerAPI:
	return Quack.get_mp()

static func get_local_mp_id() -> int:
	return MultiplayerSession.local_client.id if is_in_multiplayer() or treat_as_non_auth else 1#int(treat_as_non_auth)

static var treat_as_non_auth: bool = false
static var threaded_encoding: bool = get_threaded_encoding()
static var store_receive_replays: bool = get_store_receive_replays()
static var store_send_replays: bool = get_store_send_replays()

static func encode_threaded(callable: Callable,high_priority: bool = false,description: String = "") -> void:
	if threaded_encoding:
		Quack.ThreadUtils.add_thread(callable,high_priority,description)
	else:
		callable.call()

static func is_server() -> bool:
	return not treat_as_non_auth and Quack.is_multiplayer_authority()

static func is_in_multiplayer() -> bool:
	return peer != null# or not get_mp().multiplayer_peer is OfflineMultiplayerPeer

static func is_client() -> bool:
	return not is_server() and is_in_multiplayer()

const OwnerID = preload("res://gameplay/owner_id.gd")
static func is_node_local(node: Node) -> bool:
	var client := OwnerID.get_node_client_owner(node)
	#if node.is_multiplayer_authority() != (client and client == MultiplayerSession.local_client):
		#Console.push_err("%s %s %s Fuck!"%[node.name,node.get_multiplayer_authority(),OwnerID.get_node_owner_id(node)])
	return client and client == MultiplayerSession.local_client
	#return client and client.id == Quack.get_local_mp_id() # alt way of doing it idk
	#return OwnerID.node_is_owned_by(node,Quack.get_local_mp_id()) # old way, doesnt respect players

## Returns true if a node belongs to a remote client. Otherwise (the node is owned
## by a local client or has no client owner) returns false.
static func is_node_remote(node: Node) -> bool:
	var client := OwnerID.get_node_client_owner(node)
	if not client:
		return false
	return client != MultiplayerSession.local_client

static func is_player_local(player: MultiplayerSession.QuackPlayer) -> bool:
	return player.client == MultiplayerSession.local_client
	#return player.client.id == Quack.get_local_mp_id() # alt way of doing it idk

static func set_interp_mode_by_locality(node: Node) -> void:
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF if is_node_local(node) else Node.PHYSICS_INTERPOLATION_MODE_INHERIT

static func node_has_local_authority(node: Node) -> bool:
	return (not treat_as_non_auth) and (Quack.is_multiplayer_authority() or is_node_local(node))

## Signature offset in a given serialized format of something. The offset of
## a signature is always going to be the first byte, regardless of the size
## of the signature, or the remainder of whatever is serialized.
const SIGNATURE = 0

static func try_create_bound_server(port: int, max_clients: int) -> Error:
	var err: Error
	for i in NUM_PORTS_TO_TRY:
		err = peer.create_server(port+i,max_clients,max_channels,get_max_receive_bandwidth(false),get_max_send_bandwidth(false))
		if err == OK:
			return err
		else:
			Console.writerr("Failed to create server on port %s. Error %s."%[port+i,error_string(err)])
	return err

const NUM_PORTS_TO_TRY = 50
static func create_server(map_filepath: String, max_players: int, max_spectators: int, max_clients: int, tickrate: int,
_snapshot_tickrate: int, port: int) -> void:
	assert(tickrate > 9,"Servers shouldn't run at a tickrate lower than 10. %s is too small."%[tickrate])# and snapshot_tickrate > 0)
	assert(max_players+max_spectators <= max_clients,"%s is not enough maximum clients allowed to connect to a server. Servers must accomodate enough clients to accomodate up to maximum players (%s) + maximum spectators (%s)."%[max_clients,max_players,max_spectators])
	await await_packets_ready()
	#if !Resources.resources_ready:
		#return Console.writerr("Can't start a game yet! Resources haven't been fully loaded.")
	if Engine.get_physics_ticks_per_second() != tickrate:
		Tickrate.set_physics_simulation_rate(tickrate)
	reset_if_connected()
	setup_new_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	var err: Error = try_create_bound_server(port,max_clients)
	if err != OK:
		Console.writerr("Failed to create server on ports %s - %s. All ports returned errors."%[port,port+NUM_PORTS_TO_TRY-1])
		return reset()
	else:
		var host := peer.get_host()
		host.compress(get_network_compression_mode())
		port = host.get_local_port()
		Console.write("Created server on port %s\nMax players: %s\nMax spectators: %s\nMax clients: %s\nTickrate: %s\nMap: %s"%
	[port,max_players,max_spectators,max_clients,tickrate,map_filepath])
	setup_server_connections()
	assign_multiplayer_peer(peer)
	MultiplayerSession.max_players = max_players
	MultiplayerSession.max_spectators = max_spectators
	Quack.change_scene(map_filepath)
	Console.push_warn("Normally would update gamestate vars here")
	#GameState.max_players = max_players
	#GameState.max_spectators = max_spectators
	#GameState.max_clients = max_clients
	#server_browser.stop_listening() # maybe don't, so that ppl can look for other games
	server_browser.stop_broadcasting()
	server_browser.begin_broadcasting(
		ServerBrowser.create_selfserver_packet(port)
	)

static func create_dedicated_server(map_filepath: String, max_players: int, max_spectators: int,
tickrate: int, snapshot_tickrate: int, port: int) -> void:
	Console.write("Attempting to host dedicated server on "+map_filepath)
	create_server(
		map_filepath,
		max_players,
		max_spectators,
		max_players+max_spectators,
		tickrate,
		snapshot_tickrate,
		port
	)
	WindowUtils.append_to_window_title(" (SERVER)")

static func host(map_filepath: String, max_players: int, max_spectators: int, tickrate: int,
snapshot_tickrate: int, port: int) -> void:
	Console.write("Attempting to host game on "+map_filepath)
	create_server(
		map_filepath,
		max_players,
		max_spectators,
		max_players+max_spectators,
		tickrate,
		snapshot_tickrate,
		port
	)
	WindowUtils.append_to_window_title(" (HOST)")

static func setup_new_peer(mode: int = SERVER) -> void:
	assert(mode == SERVER or mode == MultiplayerPeer.TARGET_PEER_BROADCAST,"Targeting mode %s is incorrect. Target mode either needs to be set to target the server, %s, or set to broadcast, %s."%[mode,SERVER,MultiplayerPeer.TARGET_PEER_BROADCAST])
	var new_peer := ENetMultiplayerPeer.new()
	new_peer.set_target_peer(mode)
	new_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	#new_peer.set_transfer_channel(1)
	peer = new_peer

static func assign_multiplayer_peer(new_peer: MultiplayerPeer) -> void:
	get_mp().set_multiplayer_peer(new_peer)

static func reset() -> void:
	Console.write("Resetting peer")
	var scene := Quack.get_current_scene()
	scene.set_physics_process(false)
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	if peer:
		peer.close()
	peer = null
	treat_as_non_auth = false
	Tickrate.reset_tickrate()
	assign_multiplayer_peer(OfflineMultiplayerPeer.new())
	disconnect_mp_signals()
	# disconnect peer connections
	# disconnect tick funcs
	# reset vars
	
	Serializer.uid_map.clear()
	Serializer.uid_index = 0
	Inputs.input_signature = 0
	# emit network ended signal
	# save history
	# this is hacky and dumb as fuck
	Quack.change_scene(ProjectSettings.get_setting("application/run/main_scene"))
	WindowUtils.reset_window_title()
	if get_online():
		ConnectivityTester.test_internet_connection()
	server_browser.stop_broadcasting()
	jitter_hist.fill(0)

static func disconnect_mp_signals() -> void:
	@warning_ignore("static_called_on_instance")
	Quack.disconnect_all_signals(Quack.multiplayer,[Quack.Network,NetworkPackets,NetworkPackets.PacketType])

static func multiplayer_connected() -> bool:
	return peer != null

static func reset_if_connected() -> void:
	if multiplayer_connected():
		reset()

static func get_sender_id() -> int:
	return get_mp().get_remote_sender_id()

static func await_packets_ready() -> bool:
	while not NetworkPackets.PacketType.ready or not QuackMultiplayer.ready:
		await Quack.tree.physics_frame
	return true

static func connect_to_server(ip: String = localhost, port: int = DEFAULT_PORT) -> void:
	await await_packets_ready()
	Console.write("Attempting to connect to server %s on port %s"%[ip,port])
	#if !Resources.resources_ready:
		#return Console.writerr("Can't start a game yet! Resources haven't been fully loaded.")
	reset_if_connected()
	setup_new_peer()
	if NetDebug.lag_faker_active():
		var connection_err := NetDebug.lag_faker.connect_to_server(ip,port)
		if connection_err != OK:
			return Console.writerr("Couldn't connect to %s:%s. Lag faker connection returned error %s."%[ip,port,error_string(connection_err)])
		var enet_peer_err := NetDebug.lag_faker.connect_enet_peer(peer)
		if enet_peer_err != OK:
			return Console.writerr("Couldn't connect enet peer. Got error %s."%error_string(enet_peer_err))
	else:
		var err := peer.create_client(ip,port,channel_count,get_max_receive_bandwidth(true),get_max_send_bandwidth(true),)
		if err != OK:
			return Console.writerr("Couldn't create client connecting to %s:%s. Got error %s."%[ip,port,error_string(err)])
		else:
			var host := peer.get_host()
			host.compress(get_network_compression_mode())
			if client_port_bound:
				Console.write("Created client on port %s."%host.get_local_port())
			else:
				Console.write("Created client on unbound port.")
	assign_multiplayer_peer(peer)
	setup_client_connecting_connections()

static func setup_client_connecting_connections() -> void:
	var multiplayer: MultiplayerAPI = get_mp()
	multiplayer.connected_to_server.connect(on_connection_succeeded)
	multiplayer.connection_failed.connect(on_connection_failed)

static func setup_server_connections() -> void:
	@warning_ignore("shadowed_variable_base_class")
	var multiplayer: MultiplayerAPI = get_mp()
	multiplayer.peer_connected.connect(on_peer_connected)
	multiplayer.peer_disconnected.connect(on_peer_disconnected)
	(multiplayer as SceneMultiplayer).peer_packet.connect(NetworkPackets.server_receive)

static func setup_client_connections() -> void:
	var multiplayer: MultiplayerAPI = get_mp()
	multiplayer.server_disconnected.connect(on_server_disconnected)
	(multiplayer as SceneMultiplayer).peer_packet.connect(NetworkPackets.client_receive)

static func get_hostname_win() -> String:
	return IP.resolve_hostname(OS.get_environment("COMPUTERNAME"),IP.TYPE_IPV4)

static func get_hostname_unix() -> String:
	return IP.resolve_hostname(OS.get_environment("HOSTNAME"),IP.TYPE_IPV4)

static func get_hostname_desktop() -> String:
	if OS.has_feature("windows"):
		return get_hostname_win() 
	elif OS.has_feature("x11") or OS.has_feature("OSX"):
		return get_hostname_unix()
	else:
		return "Not Desktop"

static func get_loopback_hostname() -> String:
	return IP.resolve_hostname(loopback)

static func get_localhost_hostname() -> String:
	return IP.resolve_hostname(localhost)

static func on_peer_disconnected(peer_id: int) -> void:
	Console.broadcast("Peer %s disconnected."%peer_id)
	MultiplayerSession.remove_client(peer_id)
	#if GameState.clients.has(peer_id):
		#GameState.remove_client(peer_id)

# Client connection funcs
static func on_connection_succeeded() -> void:
	Console.write("Connection succeeded!")
	var id := Quack.multiplayer.get_unique_id()
	disconnect_mp_signals()
	setup_client_connections()
	var client := MultiplayerSession.add_local_client(id,0)
	client.set_info(
		get_max_command_frame_rate(true),
		get_preferred_buffer_length(),
		get_preferred_input_buffer_length(),
		get_preferred_server_input_buffer_length(),
		get_max_receive_bandwidth(true),
		get_max_send_bandwidth(true)
	)
	client.send_info()
	begin_net_receive_tracking()

static func on_connection_failed() -> void:
	Console.write("Connection failed.")
	reset()

# Client funcs
static func on_server_disconnected() -> void:
	Console.write("Server disconnected.")
	reset.call_deferred()

static func on_peer_connected(peer_id: int) -> void:
	Console.broadcast("Peer %s connected."%peer_id)
	Console.push_warn("Normally would check if gamestate can accept a new client here")
	NetworkPackets.ServerInfoPacket.send_to_client(peer_id)
	MultiplayerSession.add_client(peer_id,0)
	#if GameState.can_accept_new_client():
		#send_packet_to_peer(peer_id,GameState.get_server_info(),MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	#else:
		#Console.write("Peer %s denied. No room for new client. (%s/%s clients, %s/%s players, %s/%s spectators.)"%
		#[peer_id,GameState.num_clients,GameState.max_clients,
		#GameState.num_players,GameState.max_players,
		#GameState.num_spectators,GameState.max_spectators])
		#
#		# forcibly disconnect peer because it doesn't emit peer_disconnected
#		# which would call on_peer_disconnected and would try to remove a
#		# nonexistent client.
		#peer.disconnect_peer(peer_id,true)

static func send_packet_to_peer(peer_id: int, packet: PackedByteArray, transfer_mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE) -> void:
	assert(transfer_mode <= MultiplayerPeer.TRANSFER_MODE_RELIABLE and transfer_mode >= MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, "transfer_mode must be a number between %s and %s, but was passed as %s."%[MultiplayerPeer.TRANSFER_MODE_RELIABLE,MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,transfer_mode])
	Console.write_if_error((Quack.multiplayer as SceneMultiplayer).send_bytes(packet,peer_id,transfer_mode))
	# maybe at some point turn this func (which returns an error) into something
	# that checks for and prints errors

static func clamp_allow_0(value: int, min_val: int, max_val: int) -> int:
	return 0 if value == 0 else clampi(value,min_val,max_val)

const MAX_COMMAND_FRAMERATE = 300
const MIN_COMMAND_FRAMERATE = 10
static func get_max_command_frame_rate(client: bool) -> int:
	return ProjectSettings.get_setting_safe(CLIENT_COMMAND_FRAME_RATE_SETTING_PATH if client else HOST_COMMAND_FRAME_RATE_SETTING_PATH,0)

const MAX_BUFFER_LENGTH = .2
static func get_preferred_buffer_length() -> float:
	return ProjectSettings.get_setting_safe(PREFERRED_BUFFER_SIZE_SETTING_PATH,0.)

const MAX_INPUT_BUFFER_LENGTH = .2
static func get_preferred_input_buffer_length() -> float:
	return ProjectSettings.get_setting_safe(PREFERRED_INPUT_BUFFER_LENGTH_SETTING_PATH,0.)

const MAX_SERVER_INPUT_BUFFER_LENGTH = .2
static func get_preferred_server_input_buffer_length() -> float:
	return ProjectSettings.get_setting_safe(PREFERRED_SERVER_INPUT_BUFFER_TIME_SETTING_PATH,0.)

const MAX_BANDWIDTH = 6250000
const MIN_BANDWIDTH = 65535
static func get_max_send_bandwidth(client: bool) -> int:
	return ProjectSettings.get_setting_safe(MAX_SEND_CLIENT_SETTING_PATH if client else MAX_SEND_HOST_SETTING_PATH,0)

static func get_max_receive_bandwidth(client: bool) -> int:
	return ProjectSettings.get_setting_safe(MAX_RECEIVE_CLIENT_SETTING_PATH if client else MAX_RECEIVE_HOST_SETTING_PATH,0)

static func get_network_compression_mode() -> ENetConnection.CompressionMode:
	return ProjectSettings.get_setting_safe(COMPRESSION_SETTING_PATH,ENetConnection.COMPRESS_NONE) as ENetConnection.CompressionMode

static func get_threaded_encoding() -> bool:
	return ProjectSettings.get_setting_safe(THREADED_ENCODING_SETTING_PATH,false) as bool

static func get_online() -> bool:
	return ProjectSettings.get_setting_safe(ONLINE_SETTING_PATH,true) as bool

static func get_store_send_replays() -> bool:
	return ProjectSettings.get_setting_safe(STORE_SEND_REPLAYS_SETTING_PATH,false) as bool

static func get_store_receive_replays() -> bool:
	return ProjectSettings.get_setting_safe(STORE_RECEIVE_REPLAYS_SETTING_PATH,false) as bool
