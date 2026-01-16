const RecentFrame = preload("res://network/multiplayer/recent_frame.gd")
const MultiplayerSession = preload("res://network/multiplayer/multiplayer_session.gd")
const Serializer = preload("res://gameplay/serializer.gd")
const SerializedNodeCollection = Serializer.SerializedNodeCollection
const StreamPeerBitBuffer = preload("res://utils/stream_peer_bit_buffer.gd")
const Fuckup = Quack.Network.NetworkPackets.SerializationFuckupPacket
const QuackMultiplayer = preload("res://network/multiplayer/quack_multiplayer.gd")

var num: int
var serializations: Dictionary[int,SerializedNodeCollection] # ints are UIDs
#const node_is_visible = true

func restore(scene: Node) -> void:
	# Remove UIDs that dont exist on this frame
	var uids := Serializer.uid_map.keys()
	for uid:int in uids:
		# NOTE there could maybe be a faster way of doing this. I.e. if there
		# IS a serializer on this frame, update it here and then dont apply any
		# updates to it when going thru spawning serializations.
		if not serializations.has(uid):
			Serializer.uid_map[uid].owner.queue_free()
	
	# Spawn / update UIDs that exist on this frame
	for uid:int in serializations:
		if Serializer.uid_map.has(uid):
			Serializer.uid_map[uid].receive_instant_update(serializations[uid].property_lists)
		else:
			serializations[uid].spawn(scene)

# Kinda an incorrect name tbh
func merge(frame: RecentFrame) -> void:
	num = frame.num
	var uids := frame.serializations.merged(serializations)
	for uid in uids.keys():
		# Exists in new frame
		if frame.serializations.has(uid):
			serializations[uid] = frame.serializations[uid]
		# Doesn't exist in new frame
		else:
			var serialization := serializations[uid]
			if not serialization.was_deleted():
				serialization.frame_deleted = num

func _init(serialized_nodes: Array[SerializedNodeCollection], frame_num: int = MultiplayerSession.frame_num) -> void:
	num = frame_num
	for node in serialized_nodes:
		serializations[node.uid] = node

# Alternate get delta logic NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE
#	var spawned_nodes: Array[SerializedNodeCollection]
	#var delta_nodes: Array[SerializedNodeCollection]
	#
	#for uid in all_uids.keys():
		#if serializations.has(uid):
			#var serialized_node := serializations[uid]
			#if serialized_node.was_deleted():
				## Ok im kinda uncomfortable with this but the way that things
				## work now is that replays check if the current frame has a UID
				## and network stuff checks if the node is marked as deleted...
				## bruhhhhhh
				#NetworkedNode.encode_owner_delete(uid,buffer)
			#elif prev_frame.serializations.has(uid):
				#NetworkedNode.encode_owner_delta(buffer)
				#delta_nodes.append(serialized_node)
			#else:
				#NetworkedNode.encode_owner_spawn(uid,serialized_node.scene_id,buffer)
				#spawned_nodes.append(serialized_node)
	#
	#for node in spawned_nodes:
		#node.encode_spawn(buffer,Property.VisibilityType.OWNER_ONLY)
	#for node in delta_nodes:
		#node.encode_delta(prev_frame.serializations[node.uid],buffer,Property.VisibilityType.OWNER_ONLY)

func get_delta(prev_frame: RecentFrame, receiver_id: int = 0, hostility_mask: int = 0) -> PackedByteArray:
	var buffer := StreamPeerBitBuffer.new(65535,1024)
	
	var all_uids: Dictionary[int,SerializedNodeCollection] = serializations.merged(prev_frame.serializations)
	all_uids.sort()
	
	if receiver_id != 0:
		buffer.put_u64(hostility_mask)
	
	for uid in all_uids.keys():
		if serializations.has(uid): # Node is in current frame
			var serialized_node := serializations[uid]
			
			# Ok im kinda uncomfortable with this but the way that things
			# work now is that replays check if the current frame has a UID
			# and network stuff checks if the node is marked as deleted...
			# bruhhhhhh
			if serialized_node.was_deleted():
				NetworkedNode.encode_owner_delete(uid,buffer)
				continue
			
			var vis_type:= Property.VisibilityType.OWNER_ONLY
			#var vis_type: Property.VisibilityType = Property.get_visibility(serialized_node.owner_id,serialized_node.team,receiver_id,hostility_mask)
			if prev_frame.serializations.has(uid): # Delta node
				NetworkedNode.encode_owner_delta(buffer)
				#if receiver_id > 0:
					#Console.write.call_deferred("%s %s"%[uid,Property.VisibilityType.find_key(vis_type)])
				serialized_node.encode_delta(prev_frame.serializations[uid],buffer,vis_type)
			else: # Newly spawned node
				NetworkedNode.encode_owner_spawn(uid,serialized_node.scene_id,buffer)
				#if receiver_id > 0 and prev_frame.num < 1 and num < 50:
					#Console.write.call_deferred("S f %s uid %s sid %s bp %s vp %s"%[
						#num,uid,serialized_node.scene_id,buffer.bool_position,buffer.get_var_pos()
					#])
				serialized_node.encode_spawn(buffer,Property.VisibilityType.OWNER_ONLY)
		else: # Node was deleted between prev frame and current frame
			NetworkedNode.encode_owner_delete(uid,buffer)
	
	return buffer.export()

func decode_delta(delta: PackedByteArray, receiver_id: int, frame_num: int, delta_frame_num: int) -> void:
	var max_bool_idx := delta.decode_u32(0)
	var buffer := StreamPeerBitBuffer.decode(delta)
	var serializers := Serializer.get_serializers()
	var idx: int = 0
	var scene := Quack.get_current_scene()
	var hostility_mask := buffer.get_u64() if receiver_id != 0 else 0xFFFFFFFFFFFFFFF
	
	
	while buffer.bool_position < max_bool_idx:
		
		if buffer.get_bool(): # Updated
			if buffer.get_bool(): # Delta
				var serializer := serializers[idx]
				var vis_type:= Property.VisibilityType.OWNER_ONLY
				#var vis_type := Property.get_visibility(serializer.serialized.owner_id,serializer.serialized.team,receiver_id,hostility_mask)
				#Console.write("%s %s %s"%[serializer.uid,idx,Property.VisibilityType.find_key(vis_type)])
				serializer.decode_delta(buffer, vis_type)
				idx += 1
				#Console.write("%s-->%s Delta updating %s (%s), index increasing to %s."%[
				#delta_frame_num,frame_num,serializers[idx-1].uid,serializers[idx-1].owner.name,idx
				#])
			else: # Not delta
				if buffer.get_bool(): # Spawned
					var uid := buffer.get_u32()
					var scene_id := buffer.get_u8()
					#Console.write("C f %s uid %s sid %s bp %s vp %s"%[
						#frame_num,uid,scene_id,buffer.bool_position,buffer.get_var_pos()
					#])
					#var bleh := Serializer.uid_map
					if serializations.has(uid): # Redundant spawn
						if Serializer.uid_map.has(uid): # Apply changes to existing node
							if serializers.size() <= idx:
								Fuckup.send(0,serializers.size(),idx,uid,scene_id,delta_frame_num,frame_num)
								MultiplayerSession.clients[receiver_id].fucked = true
								return
							if serializers[idx] != Serializer.uid_map[uid]:
								Fuckup.send(1,idx,serializers[idx].uid,uid,scene_id,delta_frame_num,frame_num)
								MultiplayerSession.clients[receiver_id].fucked = true
								return
							# The above fuckup stuff replaces this assertion
							#assert(serializers[idx] == Serializer.uid_map[uid], "%s != %s, delta from frame %s to %s"%[
								#serializers[idx].uid, uid, delta_frame_num,frame_num
							#])
							serializers[idx].decode(buffer,Property.VisibilityType.OWNER_ONLY)
							#Serializer.uid_map[uid].decode(buffer)
						else: # Node was deleted between this frame and whatever
							  # frame the server knows the client received. this
							  # client has already deleted the node, so instead
							  # of applying anything, this decodes without applying
							  # it to any nodes.
							serializations[uid].decode_spawn(buffer,Property.VisibilityType.OWNER_ONLY)
						idx += 1
						#Console.write("%s-->%s Already spawned node %s (%s), index increasing to %s."%[
							#delta_frame_num,frame_num,uid,Serializer.uid_map[uid].owner.name,idx
						#])
					else:
						# New
						Serializer.uid_index = uid
						var node := QuackMultiplayer.scenes[scene_id].instantiate()
						scene.add_child(node)
						var serializer := Serializer.component_list[node]
						serializer.decode(buffer,Property.VisibilityType.OWNER_ONLY)
						#Console.write("%s-->%s Spawning new node %s (%s), index staying at %s."%[
							#delta_frame_num,frame_num,uid,Serializer.uid_map[uid].owner.name,idx
						#])
				else: # Deleted
					var uid := buffer.get_u32()
					if Serializer.uid_map.has(uid):
						Serializer.uid_map[uid].owner.queue_free()
						idx += 1
						#Console.write("%s-->%s Deleting node %s (%s), index increasing to %s."%[
							#delta_frame_num,frame_num,uid,Serializer.uid_map[uid].owner.name,idx
						#])
					#else:
						#Console.write("%s-->%s Already deleted node %s, index staying at %s."%[
							#delta_frame_num,frame_num,uid,idx
						#])
		else: # Not updated
			idx += 1
			#Console.write("%s-->%s Not updating %s (%s), index increasing to %s."%[
				#delta_frame_num,frame_num,serializers[idx].uid,serializers[idx].owner.name,idx
			#])
	
	# FIXME this will accumulate on clients over time lmao
	for serializer in Serializer.get_serializers():
		serializations[serializer.uid] = serializer.serialized
	num = frame_num
