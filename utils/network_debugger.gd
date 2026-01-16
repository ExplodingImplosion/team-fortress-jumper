const Network = Quack.Network
const BBCode = Console.BBCode # Probably bad practice to grab this from Console, which isn't a traditional 'global accessor' type beat, but fuck it lmao
const TimeUtils = Quack.TimeUtils

const num_ports_to_try = 100

static var lag_faker: LagFaker

static func lag_faker_active() -> bool:
	return OS.is_debug_build() and lag_faker != null

static func get_lag_faker() -> LagFaker:
	if lag_faker_active():
		return lag_faker
	else:
		return null

static func start_lag_faker(target_address: String = Network.get_loopback_hostname(), target_port: int = Network.DEFAULT_PORT, port: int = Proxy.DEFAULT_VIRTUAL_SERVER_PORT) -> void:
	if OS.is_debug_build():
		if lag_faker == null:
			lag_faker = LagFaker.new(target_address,target_port,Network.get_loopback_hostname(),port)
			Console.write("Starting network debugger...")
		else:
			Console.push_err("Already debugging.")
	else:
		Console.push_err("Can't start debugger in non-debug build.")

static func stop_lag_faker() -> void:
	if OS.is_debug_build():
		if lag_faker != null:
			lag_faker.cleanup()
			lag_faker = null
			Console.write("Network debugger stopped.")
		else:
			Console.push_err("Not currently debugging.")
	else:
		Console.push_err("Can't end debugger in non-debug build.")

class Proxy:
	enum {DEFAULT_VIRTUAL_SERVER_PORT = 8000}
	var vclient := ProxyPeer.new()
	var vserver := ProxyPeer.new()
	
	func _init(target_address: String, target_port: int, listen_address: String = Network.get_loopback_hostname(), virtual_server_port: int = DEFAULT_VIRTUAL_SERVER_PORT) -> void:
		target_address = IP.resolve_hostname(target_address)
		Console.write("Virtual server listening to %s:%s. Virtual client sending to %s:%s."%[
			# listening to...					client sending to...
			target_address,virtual_server_port,target_address,target_port
		])
		var bind_err := vserver.bind_to(listen_address,virtual_server_port)
		if bind_err != OK:
			Console.push_err("Virtual server binding failed (%s)."%error_string(bind_err))
		var target_err := change_target(target_address,target_port)
		if target_err != OK:
			Console.push_err("Virtual client binding failed (%s)."%error_string(target_err))
	
	func cleanup() -> void:
		vserver.close()
		vclient.close()
		vserver = null
		vclient = null
	
	func get_target_address() -> String:
		return vclient.target_address
	
	func get_target_port() -> int:
		return vclient.target_port
	
	func get_listen_address() -> String:
		return vserver.bound_address
	
	func get_listen_port() -> int:
		return vserver.bound_port
	
	func change_target(address: String, port: int) -> Error:
		return vclient.target(address,port)

class ProxyPeer:
	extends PacketPeerUDP
	
	var bound_port: int
	var bound_address: String
	var target_port: int
	var target_address: String
	var has_target: bool
	const num_port_bind_retry_attempts = 10
	# PacketPeerUDP has this as a function
	#var is_bound: bool
	
	func target(address: String, port: int) -> Error:
		var try_target: int = set_dest_address(address,port)
		if try_target != OK:
			Console.push_err("Couldn't set destination address to %s with port %s. %s."%[address,port,error_string(try_target)])
			return try_target
		target_address = address
		target_port = port
		has_target = true
		return OK # or try_target or 0
	
	func bind_to(address: String, port: int) -> Error:
		var bind_attempt: Error
		for i in num_port_bind_retry_attempts:
			bind_attempt = bind(port,address)
			if bind_attempt == OK:
				break
			Console.push_err("Couldn't bind to address %s on port %s. %s."%[address,port,error_string(bind_attempt)])
			port += 1
		bound_address = address
		bound_port = port
		return bind_attempt
	
	func target_packet_source() -> void:
		# technically this isn't true, but for the only case I've used it, I don't
		# want proxy peers to change their target
		assert(!has_target, "Can't target packet source if proxy peer already has a target.")
		var packet_port: int = get_packet_port()
		var packet_address: String = get_packet_ip()
		Console.write("Targeting %s:%s from %s."%[packet_address,packet_port,get_local_port()])
		target(packet_address,packet_port)

class FakeLagParams:
	## The minimum amount of latency, in usec, that will be added.
	var fake_min_latency_usec: int
	## The amount of time, in usec, it will
	var fake_loss: int
	## The maximum amount of latency, in usec, that will be added to
	## [member fake_min_latency_usec].
	var fake_jitter_usec: int
	## The amount of jitter
	var fake_jitter_variance: float
	## A repeating pattern for jitter to use.
	var jitter_pattern: Curve
	## A repeating pattern to determine when to 'lose' packets.
	var loss_pattern: Curve
	## Weird place to put this, but this keeps track of how many packets have
	## been "processed"
	var num_packets: int
	
	var rng := RandomNumberGenerator.new()
	
	var jitter_mode: LAG_MODE
	var loss_mode: LAG_MODE
	
	enum LAG_MODE {
		PACKET_INTERVAL,
		TIME,
	}
	
	func get_latency(time: int) -> int:
		return time + fake_min_latency_usec + get_jitter()
	
	func packet_loss_algo(i: int) -> bool:
		if fake_loss:
			return i % fake_loss == 0
		else:
			return false
	
	## Returns whether or not a packet should be lost
	func lose_packet() -> bool:
		if loss_pattern:
			pass
		
		if loss_mode == LAG_MODE.PACKET_INTERVAL:
			return packet_loss_algo(num_packets)
		if loss_mode == LAG_MODE.TIME:
			return packet_loss_algo(Time.get_ticks_usec())
		#@warning_ignore("assert_always_false")
		assert(false, "invalid loss mode.")
		return false
	
	## Returns the total amount of jitter that should be added
	func get_jitter() -> int:
		@warning_ignore("narrowing_conversion")
		return fake_jitter_usec * get_jitter_variance()
	
	var jitter_pos: int = 0
	func get_jitter_variance() -> float:
		if !jitter_pattern:
			return rng.randf_range(-1.,1.) * fake_jitter_variance
		jitter_pos = wrapi(jitter_pos + 1,0,jitter_pattern.bake_resolution)
		return jitter_pattern.sample_baked(float(jitter_pos) / jitter_pattern.bake_resolution)
	

class LagFaker:
	
	var client_params := FakeLagParams.new()
	var server_params := FakeLagParams.new()
	
	var proxy: Proxy
	
	var out_queue := PacketQueue.new()
	var in_queue := PacketQueue.new()
	
	var store_packets: bool
	
	signal out_queue_filled
	signal in_queue_filled
	
	var print_out_queue: bool
	var print_in_queue: bool
	
	var notify_out_queue_filled: bool
	var notify_in_queue_filled: bool
	
	const out_string = "[color=ffff00]Out queue (send):[/color]"
	const in_string = "[color=ffff00]In queue (receive):[/color]"
	
	func check_out_queue(callable: Callable, flags: int = 0) -> void:
		out_queue_filled.connect(callable.bind(out_queue),flags)
	
	func check_in_queue(callable: Callable, flags: int = 0) -> void:
		in_queue_filled.connect(callable.bind(in_queue),flags)
	
	func _init(target_address: String, target_port: int, listen_port: String = Network.get_loopback_hostname(), in_port: int = Proxy.DEFAULT_VIRTUAL_SERVER_PORT) -> void:
		Console.write("Creating fake lag instance listening on port %s."%in_port)
		
		if not OS.is_debug_build():
			Console.push_err("Creating fake lag instance in non-debug game.")
			free()
		proxy = Proxy.new(target_address,target_port,listen_port,in_port)
		Quack.connect_callable_to_frame_starts(process_packets)
	
	func connect_to_server(address: String, port: int) -> Error:
		Console.write("Lag faker connecting to %s on port %s."%[address,port])
		return proxy.change_target(address,port)
	
	func connect_enet_peer(peer: ENetMultiplayerPeer, channel_count: int = 0, in_bandwidth: int = 0, out_bandwidth: int = 0, local_port: int = 0) -> Error:
		var vserveraddy := get_virtual_server_address()
		var vserverport := get_virtual_server_port()
		Console.write("Connecting ENetMultiplayerPeer to fake lag virtual server at %s on port %s."%[vserveraddy,vserverport])
		var err: Error = peer.create_client(vserveraddy,vserverport,channel_count,in_bandwidth,out_bandwidth,local_port)
		if err != OK:
			Console.writerr("Creating client failed. Got error %s."%error_string(err))
			Console.writerrverb("Additional info:\nchannel_count: %s\nin_bandwidth: %s\nout_bandwidth: %s\nlocal_port:%s"%[channel_count,in_bandwidth,out_bandwidth,local_port])
		return err
	
	func get_target_address() -> String:
		return proxy.get_target_address()
	
	func get_target_port() -> int:
		return proxy.get_target_port()
	
	func get_virtual_server_address() -> String:
		return proxy.get_listen_address()
	
	func get_virtual_server_port() -> int:
		return proxy.get_listen_port()
	
	func process_packets() -> void:
		var time: int = Time.get_ticks_usec()
		# virtual server receives packets from client and adds them to queue
		add_packets(proxy.vserver,out_queue,time,client_params)
		# virtual client receives packet from server and adds them to queue
		add_packets(proxy.vclient,in_queue,time,server_params)
		if not out_queue.is_empty():
			if notify_out_queue_filled:
				out_queue_filled.emit()
			if print_out_queue:
				Console.write("%s %s"%[out_string,BBCode.set_color(str(out_queue),Color.CYAN)])
		if not in_queue.is_empty():
			if notify_in_queue_filled:
				in_queue_filled.emit()
			if print_in_queue:
				Console.write("%s %s"%[in_string,BBCode.set_color(str(in_queue),Color.SKY_BLUE)])
		# processes client packets and sends them to server
		out_queue.process(proxy.vclient,time,store_packets)
		# processes server packets and sends them to client
		in_queue.process(proxy.vserver,time,store_packets)
	
	func add_packets(this_peer: ProxyPeer, queue: PacketQueue, timestamp: int, params: FakeLagParams) -> void:
		while this_peer.get_available_packet_count() > 0:
			add_packet(this_peer,queue,timestamp,params)

	func add_packet(this_peer: ProxyPeer, queue: PacketQueue,timestamp: int, params: FakeLagParams) -> void:
		
		params.num_packets += 1
		
		var packet: PackedByteArray = this_peer.get_packet()
		var packet_err: Error = this_peer.get_packet_error()
		if packet_err != OK:
			return Console.push_err("Fake lag instance got a packet error %s."%error_string(packet_err))
		
		if !this_peer.has_target:
			this_peer.target_packet_source()
		
		if !params.lose_packet():
			queue.add(Packet.new(packet,params.get_latency(timestamp)))
	
	func set_min_latency(amount_usec: int) -> void:
		@warning_ignore("integer_division")
		var amount_usec_half: int = amount_usec / 2
		var amount_usec_r: int = amount_usec%2
		client_params.fake_min_latency_usec = amount_usec_half+amount_usec_r
		server_params.fake_min_latency_usec = amount_usec_half
	
	func set_jitter(amount_usec: int) -> void:
		@warning_ignore("integer_division")
		var amount_usec_half: int = amount_usec / 2
		var amount_usec_r: int = amount_usec%2
		client_params.fake_jitter_usec = amount_usec_half+amount_usec_r
		server_params.fake_jitter_usec = amount_usec_half
	
	func set_jitter_variance(amount: float) -> void:
		amount = amount / 2
		client_params.fake_jitter_variance = amount
		server_params.fake_jitter_variance = amount
	
	func set_loss(amount: int) -> void:
		@warning_ignore("integer_division")
		var amount_half: int = amount / 2
		var amount_r: int = amount%2
		client_params.fake_loss = amount_half+amount_r
		server_params.fake_loss = amount_half
	
	func set_loss_curve(path: String) -> void:
		var curve: Curve = load(path)
		if !curve:
			return Console.writerr("Invalid path to Curve.")
		client_params.loss_pattern = curve
		server_params.loss_pattern = curve
	
	func set_jitter_curve(path: String) -> void:
		var curve: Curve = load(path)
		if !curve:
			return Console.writerr("Invalid path to Curve.")
		client_params.jitter_pattern = curve
		server_params.jitter_pattern = curve
	
	func cleanup() -> void:
		if proxy:
			proxy.cleanup()
			Quack.disconnect_callable_from_frame_starts(process_packets)

class Packet:
	var packet: PackedByteArray
	var timestamp_usec: int
	var send_timestamp_usec: int
	
	func _init(pckt: PackedByteArray, timestamp: int) -> void:
		packet = pckt
		timestamp_usec = timestamp
	
	func should_send(time: int) -> bool:
		return time >= timestamp_usec
	
	func send(peer: PacketPeerUDP) -> void:
		send_timestamp_usec = Time.get_ticks_usec()
		var err := peer.put_packet(packet)
		if err != OK:
			Console.write("Got error %s putting %sB packet %s from port %s."%[error_string(err),packet.size(),hash(packet),peer.get_local_port()])
	
	func _to_string() -> String:
		return "%s bytes at timestamp %s:
%s"%[packet.size(),TimeUtils.usec_to_seconds(timestamp_usec),packet]
	
	func size() -> int:
		return packet.size()

class PacketQueue:
	var history: Array[Packet]
	var queue: Array[Packet]
	
	func add(packet: Packet) -> void:
		queue.append(packet)
	func get_at(idx: int) -> Packet:
		return queue[idx]
	func remove_at(idx: int) -> void:
		queue[idx] = null
	func remove_null(num_removed: int) -> void:
		var null_idxs := PackedInt32Array()
		var min_idx: int = 0
		var min_null_idx: int = -1
		var size: int = queue.size()
		# get rid of this eventually
		var num_packets_before := get_num_packets()
		for i in size:
			if queue[i] == null:
				null_idxs.append(i)
			else:
				if !null_idxs.is_empty():
					queue[null_idxs[min_idx]] = queue[i]
					queue[i] = null
					null_idxs.append(i)
					min_idx += 1
		# get rid of this eventually
		var num_packets_after := get_num_packets()
		queue.resize(size-num_removed)
		assert(!queue.has(null))
		# get rid of these eventually
		var num_packets_after_resize := get_num_packets()
		assert(num_packets_before == num_packets_after,"%s != %s"%[num_packets_before,num_packets_after])
		assert(num_packets_after == num_packets_after_resize, "%s != %s"%[num_packets_after,num_packets_after_resize])
	
	func get_num_packets() -> int:
		var num_packets: int = 0
		for i in queue.size():
			if queue[i] != null:
				num_packets += 1
		return num_packets
	
	func process(peer: ProxyPeer, timestamp: int, store: bool = false) -> void:
		var packet: Packet
		var num_removed: int = 0
		for i in queue.size():
			packet = get_at(i)
			if packet.should_send(timestamp):
				packet.send(peer)
				if store:
					history.append(packet)
				remove_at(i)
				num_removed += 1
				assert(queue.has(null))
		remove_null(num_removed)
	
	func is_empty() -> bool:
		return queue.is_empty()
	
	func get_num_bytes() -> int:
		var num_bytes: int = 0
		for packet in queue:
			num_bytes += packet.size()
		return num_bytes
	
	func _to_string() -> String:
		var string: String
		for packet in queue:
			string += str(packet) + "\n"
		string.rstrip("\n")
		return string
