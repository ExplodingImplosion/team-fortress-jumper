const QuackMultiplayer = preload("res://network/multiplayer/quack_multiplayer.gd")
const NetworkPacket = preload("res://network/packets/packet.gd")
const Compression = preload("res://utils/compression.gd")
const Network = preload("res://network/network.gd")
const StreamPeerBitBuffer = preload("res://utils/stream_peer_bit_buffer.gd")
const MultiplayerLevel = preload("res://gameplay/level/common/multiplayer_level.gd")
const MultiplayerSession = MultiplayerLevel.MultiplayerSession

# Could totally fit some of these into a single byte lmao
enum {
	PACKET_TYPE, # 0
	TIMES_COMPRESSED, # 1
	PACKET_BEGIN_UNCOMPRESSED,# 2
	PACKET_SIZE_INDICATOR_BEGIN = PACKET_BEGIN_UNCOMPRESSED, # 2 
}
const PACKET_SIZE_INDICATOR_BYTES = 2
static var print_in_packets: bool = false
static var print_out_packets: bool = false

class PacketTypeCollection:
	var map: Dictionary[GDScript,PacketType]
	var type_list: Array[PacketType]
	var debug_name_list: PackedStringArray
	var num_types: int = 0
	
	func get_packet_type(script: GDScript) -> PacketType:
		if map.has(script):
			return map[script]
		
		var type := PacketType.new(script)
		add_packet_type(type)
		
		return type
	
	func add_packet_type(type: PacketType) -> void:
		map[type.packet_class] = type
		type.id = num_types
		type_list.append(type)
		num_types += 1

class PacketType:
	
	static var client_packets := PacketTypeCollection.new()
	static var server_packets := PacketTypeCollection.new()
	static var collection_list: Array[PacketTypeCollection] = [client_packets,server_packets]
	static var ready: bool
	# NOTE: Commented out / removed because packet encoding / decoding is now
	# threaded. Here's the thing, though. This was originally a single buffer
	# in order to reduce bool reallocations. The assumption I had when I wrote this
	# was that if packets were being decoded/encoded with hella bools, then it was
	# gonna happen pretty frequently (at least on the majority of frames). As such,
	# I figured that 1 buffer would be ideal. Maybe go back to this eventually, but
	# instead have like manually created threads or something?
	#static var packet_write_buffer := StreamPeerBitBuffer.new(65535)
	
	var packet_class: GDScript
	var id: int
	
	var property_list := NetworkedNode.new()
	
	var receivable_by: PacketReceiver
	
	const compressable_string = "compressable"
	const packet_send_mode_string = "packet_send_mode"
	const receiveable_by_string = "receivable_by"
	enum PacketReceiver {CLIENT=1,SERVER=2,BOTH=3,NEITHER=0,PACKET_RECEIVE_MAX = 4, PACKET_RECEIVE_MIN = -1}
	
	var compressable: bool
	var send_mode: MultiplayerPeer.TransferMode
	
	func _to_string() -> String:
		var string := "ID:				%s
Class:			%s
Receivable by:	%s
Send mode:		%s
Compressable:	%s
Size:			%s
Property List:"%[
	id,packet_class,(PacketReceiver.find_key(receivable_by) as String),send_mode,compressable,
	("%s bits" if not compressable and property_list.is_fixed_size else "Dynamic size, minimum %s bits")%( (property_list.fixed_size_bytes * 8) + property_list.num_bools + 8) # Add 8 bits for packet type ID
]
		for i in property_list.properties:
			string += "\n\t\t\t\t"+str(i)
		return string
	
	static func setup_packet_map() -> void:
		var cmap := (NetworkPacket as GDScript).get_script_constant_map()
		var constant: Variant
		for cname in cmap:
			constant = cmap[cname]
			if constant is GDScript and constant != PacketType and constant != Packet:
				if Packet.is_script_valid_packet(constant as GDScript):
					var type := PacketType.new(constant as GDScript)
					if type.receivable_by & PacketReceiver.CLIENT:
						if Quack.is_exported():
							Console.writeverb.call_deferred("Adding packet type %s to client receiveable packets."%Console.BBCode.set_color(str(cname),Color.CYAN))
						else:
							Console.write.call_deferred("Adding packet type %s to client receiveable packets."%Console.BBCode.set_color(str(cname),Color.CYAN))
						client_packets.add_packet_type(type)
						if OS.is_debug_build():
							client_packets.debug_name_list.append(cname)
					if type.receivable_by & PacketReceiver.SERVER:
						if Quack.is_exported():
							Console.writeverb.call_deferred("Adding packet type %s to server receiveable packets."%Console.BBCode.set_color(str(cname),Color.CYAN))
						else:
							Console.write.call_deferred("Adding packet type %s to server receiveable packets."%Console.BBCode.set_color(str(cname),Color.CYAN))
						server_packets.add_packet_type(type)
						if OS.is_debug_build():
							server_packets.debug_name_list.append(cname)
		NetworkPacket.server_receive = PacketType.decode.bind(PacketType.server_packets)
		NetworkPacket.client_receive = PacketType.decode.bind(PacketType.client_packets)
		ready = true
	
	func _init(script: GDScript = null) -> void:
		assert(script != null, "Script must not be null.")
		assert(Packet.is_script_valid_packet(script),"%s must directly inherit Packet and contain a function named _execute. Inherits %s."%[script,script.get_base_script()])
		# Leftovers from considering if packet types would be resources
		#if script == null:
			#setup.call_deferred()
			#return
		id = -1 # This needs to be changed out of the constructor
		packet_class = script
		#setup()
		
		var p_list := script.get_script_property_list()
		var property: Property
		for p_info in p_list:
			if is_valid_packet_property(p_info):
				property_list.source_script = script
				property = Property.new(p_info.name,p_info.type)
				property.precision_level = Property.name_to_precision(property.name)
				property.encode_type = Property.get_encode_type(property.network_type,property.sub_property_index,property.precision_level)
				property_list.properties.append(property)
		#property_list.setup()
		
		var consts := script.get_script_constant_map()
		# figure out if fixed size or not
		
		if consts.has(compressable_string):
			compressable = consts[compressable_string] as bool
		if consts.has(packet_send_mode_string):
			send_mode = consts[packet_send_mode_string] as MultiplayerPeer.TransferMode
		assert(consts.has(receiveable_by_string),"Packet must have a constant with the name %s."%receiveable_by_string)
		assert(consts[receiveable_by_string] is PacketReceiver, "%s must be of type PacketReceiver or int, but is %s."%[receiveable_by_string,consts[receiveable_by_string]])
		assert(consts[receiveable_by_string] != PacketReceiver.NEITHER and consts[receiveable_by_string] > PacketReceiver.PACKET_RECEIVE_MIN and consts[receiveable_by_string] < PacketReceiver.PACKET_RECEIVE_MAX, "Packet must be receivable by client, server, or both. Client receive mode is invalid.")
		receivable_by = consts[receiveable_by_string] as PacketReceiver
	
	static func is_valid_packet_property(info: Dictionary) -> bool:
		return QuackMultiplayer.is_script_variable(info)# and is_fixed_net_type
	
	func packet_encode(packet: Packet) -> PackedByteArray:
		var buffer := StreamPeerBitBuffer.new(65535)
		property_list.encode_node(packet,buffer)
		var packet_body: PackedByteArray = buffer.export()
		var encoded: PackedByteArray = [id]
		if compressable:
			packet_body = Compression.repeated_compress(packet_body)
		encoded.append_array(packet_body)
		return encoded
	
	func packet_decode(packet: PackedByteArray) -> Packet:
		if compressable:
			packet = Compression.repeated_decompress(packet)
		var packet_type := packet_class.new() as Packet
		property_list.decode(packet_type,StreamPeerBitBuffer.decode(packet))
		return packet_type
	
	static func decode(sender_id: int, packet: PackedByteArray, collection := client_packets) -> Packet:
		var packet_type := collection.type_list[packet[0]]
		if OS.is_debug_build() and NetworkPacket.print_in_packets:
			Console.write_in_color("Received %s %s."%[String.humanize_size(packet.size()),collection.debug_name_list[packet[0]]],Color.THISTLE)
		var decoded := packet_type.packet_decode(packet.slice(1))
		# Maybe don't do this here
		decoded._execute(sender_id)
		return decoded
	
	static func send_packet_to_server(packet: Packet) -> void:
		var type := server_packets.get_packet_type(packet.get_script() as GDScript) as PacketType
		if OS.is_debug_build() and NetworkPacket.print_out_packets:
			var encoded := type.packet_encode(packet)
			Console.write_in_color("Sending %s %s."%[String.humanize_size(encoded.size()),server_packets.debug_name_list[type.id]],Color.POWDER_BLUE)
			Network.send_packet_to_peer(1,encoded,type.send_mode)
		else:
			Network.send_packet_to_peer(1,type.packet_encode(packet),type.send_mode)
	
	static func send_packet_to_client(id: int, packet: Packet) -> void:
		var type := client_packets.get_packet_type(packet.get_script() as GDScript) as PacketType
		if OS.is_debug_build() and NetworkPacket.print_out_packets:
			var encoded := type.packet_encode(packet)
			Console.write_in_color.call_deferred("Sending %s %s."%[String.humanize_size(encoded.size()),client_packets.debug_name_list[type.id]],Color.POWDER_BLUE)
			Network.send_packet_to_peer.call_deferred(id,encoded,type.send_mode)
		else:
			Network.send_packet_to_peer.call_deferred(id,type.packet_encode(packet),type.send_mode)

static var server_receive: Callable
static var client_receive: Callable

class Packet:
	
	static func is_script_valid_packet(script: GDScript) -> bool:
		if (script as GDScript).get_base_script() != Packet:
			return false
		
		var times: int = 0
		for method in (script as GDScript).get_script_method_list():
			if method.name as String == "_execute":
				if times == 1:
					return true
				times += 1
		
		return false
	
	func _execute(_sender_id: int) -> void:
		pass

#region Packets sent from server --> client
class WorldStatePacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.CLIENT
	const compressable = true
	var u32_frame: int
	var u32_last_frame: int
	var u32_input_signature: int
	var u32_acked_signature: int
	var contents: PackedByteArray
	#static var num_received: int = 0
	
	static func create(frame: int, last_frame: int, packet: PackedByteArray, input_signature: int, acked_signature: int) -> WorldStatePacket:
		var ws_packet := WorldStatePacket.new()
		ws_packet.u32_frame = frame
		ws_packet.u32_last_frame = last_frame
		ws_packet.contents = packet
		ws_packet.u32_input_signature = input_signature
		ws_packet.u32_acked_signature = acked_signature
		return ws_packet

	@warning_ignore("unused_parameter")
	func _execute(sender_id: int) -> void:
		#num_received += 1
		Network.update_net_receive_time()
		if u32_frame <= MultiplayerSession.frame_num:
			return Console.writeverb(Console.BBCode.set_color("Received frame %s after receiving frame %s.",Color.ORANGE)%[u32_frame,MultiplayerSession.frame_num])
		#WorldStateConfirmationPacket.send(u32_frame)
		if Quack.get_current_scene() is MultiplayerLevel:
			MultiplayerSession.local_client.receive_worldstate(self)
	
	func _to_string() -> String:
		return "Worldstate packet: frame %s (delta %s) [%s bytes]"%[u32_frame,u32_last_frame,contents.size()]

class ServerInfoPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.CLIENT
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	var scene_path: String
	var u8_max_players: int
	var u8_max_spectators: int
	var u16_tickrate: int
	
	static func send_to_client(client_id: int) -> void:
		var packet := ServerInfoPacket.new()
		packet.scene_path = Quack.get_current_scene().scene_file_path
		#packet.u8_max_players = 
		#packet.u8_max_spectators = 
		packet.u16_tickrate = Network.Tickrate.target_physics_rate
		PacketType.send_packet_to_client(client_id,packet)
	
	func _execute(_sender_id: int) -> void:
		Quack.change_scene(scene_path)
		Network.Tickrate.set_physics_simulation_rate(u16_tickrate)
		for user in Quack.num_users:
			AddPlayerRequestPacket.send()
	
	func _to_string() -> String:
		return "Server info: level '%s' @ %shz, max players %s, max spectators %s"%[scene_path,u16_tickrate,u8_max_players,u8_max_spectators]

class ChangeTeamAcceptPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.CLIENT
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	var u8_player_index: int
	
	func _execute(_sender_id: int) -> void:
		pass

class ChangeTeamDenyPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.CLIENT
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	var u8_player_index: int
	
	func _execute(_sender_id: int) -> void:
		pass

class AddPlayerAcceptPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.CLIENT
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	
	func _execute(_sender_id: int) -> void:
		MultiplayerSession.local_client.add_player()

class AddPlayerDenyPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.CLIENT
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	
	func _execute(_sender_id: int) -> void:
		pass

#class InputConfirmationPacket extends Packet:
	#const receivable_by = PacketType.PacketReceiver.CLIENT
	#const compressable = false
	#var u32_acked_signature: int
	#var u32_current_signature: int
	#
	#static func send(client_id: int, acked_signature: int, current_signature: int) -> void:
		#var packet := InputConfirmationPacket.new()
		#packet.u32_acked_signature = acked_signature
		#packet.u32_current_signature = current_signature
		#PacketType.send_packet_to_client(client_id,packet)
	#
	#func _execute(_sender_id: int) -> void:
		#var client := MultiplayerSession.local_client
		#client.acked_input_signature = u32_acked_signature
		#client.server_input_signature = u32_current_signature

#endregion

#region Packets sent from client --> server
class InputPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.SERVER
	const compressable = true
	var u32_signature: int
	var u8_num_inputs: int
	var inputs: PackedByteArray
	
	static func send() -> void:
		var packet := InputPacket.new()
		var client := MultiplayerSession.local_client
		var players := client.players
		packet.u32_signature = client.input_signature
		var buffer := StreamPeerBitBuffer.new(1000,1024)
		var num_inputs := clampi(client.input_signature-client.acked_input_signature,0,Inputs.INPUT_BUFFER_SIZE)
		packet.u8_num_inputs = num_inputs
		for signature in num_inputs:
			for player in players:
				player.get_input(signature).encode(buffer)
		packet.inputs = buffer.export()
		PacketType.send_packet_to_server(packet)
	
	func _execute(sender_id: int) -> void:
		var client := MultiplayerSession.clients[sender_id]
		if client.input_signature >= u32_signature:
			Console.writerrverb(
				"Client %s sent an input with signature %s after sending an input with signature %s."%[
				sender_id,u32_signature,client.input_signature
			])
			return
		#InputConfirmationPacket.send(sender_id,u32_signature,client.input_signature)
		var buffer := StreamPeerBitBuffer.decode(inputs)
		var players := client.players
		#if u32_signature - client.input_signature > 1: breakpoint
		var offset := client.input_buffer_offset
		var num_new_inputs := clampi(u8_num_inputs,0,u32_signature - client.acked_input_signature)
		client.set_input_buffer_offset(u32_signature)
		for signature in num_new_inputs:
			for player in players:
				player.get_input(signature).decode(buffer)
		client.input_buffer_offset = offset
		client.acked_input_signature = u32_signature

class WorldStateConfirmationPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.SERVER
	const compressable = false
	var u32_confirmation_frame_num: int
	
	static func send(confirmation_frame_num: int) -> void:
		var packet := WorldStateConfirmationPacket.new()
		packet.u32_confirmation_frame_num = confirmation_frame_num
		PacketType.send_packet_to_server(packet)
	
	func _execute(sender_id: int) -> void:
		var scene := Quack.get_current_scene()
		if not scene is MultiplayerLevel: return
		if not u32_confirmation_frame_num > 0: return
		
		var client := MultiplayerSession.clients[sender_id]
		if not u32_confirmation_frame_num > client.most_recent_acked_frame.num: return
		
		var acked_frame := (scene as MultiplayerLevel).history_saver.get_frame(u32_confirmation_frame_num)
		client.most_recent_acked_frame = acked_frame
		
		var dirty_serializations := client.dirty_frame.serializations
		
		for uid:int in dirty_serializations.keys():
			var serialization := dirty_serializations[uid]
			if serialization.was_deleted() and serialization.frame_deleted <= u32_confirmation_frame_num:
				dirty_serializations.erase(uid)

class ChangeTeamRequestPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.SERVER
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	
	var u8_player_index: int
	
	func _execute(_sender_id: int) -> void:
		pass

class AddPlayerRequestPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.SERVER
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	
	static func send() -> void:
		PacketType.send_packet_to_server(AddPlayerRequestPacket.new())
	
	func _execute(sender_id: int) -> void:
		var client := MultiplayerSession.clients[sender_id]
		if MultiplayerSession.players.size() < MultiplayerSession.max_players and client.players.size() <= 8:
			client.add_player()
			PacketType.send_packet_to_client(sender_id,AddPlayerAcceptPacket.new())
		else:
			PacketType.send_packet_to_client(sender_id,AddPlayerDenyPacket.new())

class ClientReadyPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.SERVER
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	
	func _execute(sender_id: int) -> void:
		MultiplayerSession.mark_client_ready(sender_id)

class ClientInfoPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.SERVER
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	
	var u8_max_command_frame_rate: int = 0
	var half_buffer_time: float = 0.
	var half_input_buffer_time: float = 0.
	var half_server_input_buffer_time: float = 0.
	var u32_max_receive_bandwidth: int = 0
	var u32_max_send_bandwidth: int = 0
	
	static func create(client: MultiplayerSession.Client) -> ClientInfoPacket:
		var packet := ClientInfoPacket.new()
		
		packet.u8_max_command_frame_rate = client.max_command_frame_rate
		packet.half_buffer_time = client.buffer_time
		packet.half_input_buffer_time = client.input_buffer_time
		packet.half_server_input_buffer_time = client.server_input_buffer_time
		packet.u32_max_receive_bandwidth = client.max_receive_bandwidth
		packet.u32_max_send_bandwidth = client.max_send_bandwidth
		
		return packet
	
	func _execute(sender_id: int) -> void:
		MultiplayerSession.clients[sender_id].set_info(
			u8_max_command_frame_rate,
			half_buffer_time,
			half_input_buffer_time,
			half_server_input_buffer_time,
			u32_max_receive_bandwidth,
			u32_max_send_bandwidth
		)

class RemoteConsoleCommandPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.SERVER
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	var input: String
	
	static func send(input: String) -> void:
		var packet := RemoteConsoleCommandPacket.new()
		
		packet.input = input
		
		
	
	func _execute(_sender_id: int) -> void:
		pass

class SerializationFuckupPacket extends Packet:
	const receivable_by = PacketType.PacketReceiver.SERVER
	const compressable = false
	const packet_send_mode = MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE
	
	var u8_fuckup: int
	var data: Array
	
	static func send(fuckup: int, ...args) -> void:
		var packet := SerializationFuckupPacket.new()
		packet.u8_fuckup = fuckup
		packet.data = args
		
		Console.push_err(packet.get_fuckup_string())
		
		PacketType.send_packet_to_server(packet)
	
	func _execute(sender_id: int) -> void:
		
		var fuckup_string: String
		
		Console.push_err("Fucked up serializing %s! \n%s"%[sender_id,fuckup_string])
		Network.peer.disconnect_peer(sender_id)
	
	func get_fuckup_string() -> String:
		match u8_fuckup:
			0:
				return"Fuckup was index was greater than max serializer index. 
%s serializers, index was %s, spawn uid was %s, scene ID was %s, frame delta was %s to %s."%data
			1:
				return "Fuckup was serializer at index %s's uid %s didn't match supplied uid %s. 
scene ID was %s, frame delta was %s to %s."%data
			_:
				return "This fuckup was insane! Invalid fuckup code %s. Data was %s."%[
					u8_fuckup,data
				]

#endregion
