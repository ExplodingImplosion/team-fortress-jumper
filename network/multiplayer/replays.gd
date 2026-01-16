const REPLAY_FILEPATH = "user://replays/"
const BBCode = preload("res://utils/bbcode.gd")
const Compression = preload("res://utils/compression.gd")
const Replays = preload("res://network/multiplayer/replays.gd")
const Client = preload("res://network/multiplayer/client.gd")
const ReplayInterface = preload("res://interface/replay_interface/replay_interface.gd")
const ReplayInterfaceScene = preload("res://interface/replay_interface/replay_interface.tscn")
const Network = Quack.Network
const MPSesh = Network.MultiplayerSession
const Frame = Client.MultiplayerLevel.RecentFrame
const StreamPeerBitBuffer = Client.MultiplayerLevel.StreamPeerBitBuffer
const Serializer = Network.Serializer
const SerializedNodeCollection = Serializer.SerializedNodeCollection
const QuackMultiplayer = Quack.Network.QuackMultiplayer
const DEFAULT_INITIAL_ALLOCATION_BYTES = 6_000_000_0

#region Initial setup
static var printable_replay_filepath := OS.get_user_data_dir()+"/replays/"
static var replays_saveable: bool = false
static func setup_filepath() -> void:
	if not DirAccess.dir_exists_absolute(REPLAY_FILEPATH):
		var err := DirAccess.make_dir_absolute(REPLAY_FILEPATH)
		if err != OK:
			Console.push_err("Error %s creating replay filepath at %s."%[
				error_string(err),printable_replay_filepath
			])
		else:
			Console.writeverb("Created replay filepath at %s."%BBCode.set_color(printable_replay_filepath,Color.YELLOW))
			replays_saveable = true
	else:
		Console.writeverb("Found replay filepath at %s."%BBCode.set_color(printable_replay_filepath,Color.YELLOW))
		replays_saveable = true
#endregion

#region Instances
var buffer := StreamPeerBuffer.new()
var tickrate: int
var scene_path: String
var size: int = 0
var encoded_frames: Array[PackedByteArray]
var frames: Array[Frame]
var receiver_id := 0
var scene_registry: PackedStringArray
var valid: bool = false

func _init(scene: Node, tick_rate: int, receiver_id: int = 0, initial_allocation: int = DEFAULT_INITIAL_ALLOCATION_BYTES) -> void:
	if scene != null:
		scene_path = scene.scene_file_path
		tickrate = tick_rate
		self.receiver_id = receiver_id
		buffer.resize(initial_allocation)
		buffer.put_u8(tick_rate)
		buffer.put_u32(receiver_id)
		buffer.put_string(scene_path)
		assert(QuackMultiplayer.scenes.size() < 256)
		buffer.put_u8(QuackMultiplayer.scenes.size())
		for packed_scene in QuackMultiplayer.scenes:
			buffer.put_string(packed_scene.resource_path)
			buffer.put_u64(hash(packed_scene))

func decode(bytes: PackedByteArray) -> void:
	buffer.data_array = Compression.repeated_decompress(bytes.slice(1),bytes[0],true)
	tickrate = buffer.get_u8()
	receiver_id = buffer.get_u32()
	scene_path = buffer.get_string()
	var num_scenes := buffer.get_u8()
	scene_registry.resize(num_scenes)
	var scene: String
	for i in num_scenes:
		scene = buffer.get_string()
		if not QuackMultiplayer.scene_registry.has(scene):
			return Console.writerr("Scene '%s' is not in scene registry, therefore this replay cannot be played back!"%scene)
		scene_registry[i] = scene
		var local_hash := hash(QuackMultiplayer.scenes[QuackMultiplayer.scene_registry[scene]])
		var replay_hash := buffer.get_u64()
		if local_hash != replay_hash:
			return Console.writerr("Scene '%s' hash %s != replay hash %s, therefore this replay cannot be played back due to differing assets!"%[
				scene,local_hash,replay_hash
			])
	valid = true

static func new_from_bytes(bytes: PackedByteArray) -> Replays:
	var replay := Replays.new(null,0,0)
	replay.decode(bytes)
	return replay

static func load_from_file(path: String) -> Replays:
	var bytes := FileAccess.get_file_as_bytes(path)
	var err := FileAccess.get_open_error()
	if err != OK:
		Console.push_err("Got error %s opening replay %s."%[error_string(err),path])
		return null
	else:
		return new_from_bytes(bytes)

func append_frame(frame: PackedByteArray) -> void:
	buffer.put_u32(frame.size())
	var err := buffer.put_data(frame)
	if err != OK:
		Console.push_err("Error %s putting data into replay buffer."%error_string(err))
	else:
		size += 1

func get_frame() -> PackedByteArray:
	var frame_size: int = buffer.get_u32()
	var result := buffer.get_data(frame_size)
	if result[0] as Error != OK:
		Console.push_error("Error %s getting data from replay buffer."%error_string(result[0] as Error))
	else:
		size += 1
	return result[1] as PackedByteArray

func get_filename() -> String:
	return "%s (%s).REPLAY"%[scene_path.get_file().get_basename(),Quack.get_datetime_string()]

func save(fname: String = get_filename(), compression_mode: FileAccess.CompressionMode = FileAccess.COMPRESSION_ZSTD) -> void:
	if not replays_saveable:
		Console.writerr.call_deferred("Can't save replay because replays are not saveable.")
		return
	var fprint := BBCode.set_color_by_type(printable_replay_filepath+fname)
	var file := FileAccess.open(REPLAY_FILEPATH+fname,FileAccess.WRITE)
	if file == null:
		Console.writerr.call_deferred("Couldn't open file %s to save replay. Got error %s."%[fprint,error_string(FileAccess.get_open_error())])
		return
	file.store_8(compression_mode)
	file.store_buffer(Compression.repeated_compress(buffer.data_array.slice(0,buffer.get_position()),compression_mode,true))
	# Sometimes replays are stored after someone (me) unceremoniously quits the
	# game, Console has been freed by the time that this thread finishes up.
	if is_instance_valid(Console):
		Console.write.call_deferred("Stored %s replay to %s."%[BBCode.set_color(String.humanize_size(file.get_position()),BBCode.get_type_color(TYPE_INT)),fprint])
		Console.writeverb.call_deferred("Saved %s by compressing."%[
			String.humanize_size(buffer.get_position()-file.get_position())
		])
	else:
		print_rich.call_deferred("Stored %s replay to %s."%[BBCode.set_color(String.humanize_size(file.get_position()),BBCode.get_type_color(TYPE_INT)),fprint])
		if OS.is_stdout_verbose():
			print_rich.call_deferred("Saved %s by compressing."%[
			String.humanize_size(buffer.get_position()-file.get_position())
		])

var replay_client: Client
static var replay_interface: ReplayInterface
func play() -> void:
	if not valid:
		return Console.writerr("Replay is invalid.")
	var num_bytes := buffer.get_size()
	var frame_num: int = 1
	var prev_frame := Frame.new([],0)
	while buffer.get_position() < num_bytes:
		var encoded := get_frame()
		encoded_frames.append(encoded)
		var frame := Frame.new([],frame_num)
		decode_encoded_frame(frame,encoded,frame_num,prev_frame)
		frames.append(frame)
		prev_frame = frame
		frame_num += 1
	frames.resize(size)
	await Network.await_packets_ready()
	Network.treat_as_non_auth = true
	replay_client = MPSesh.add_dummy_client(0)
	MPSesh.local_client = replay_client
	if not replay_interface:
		replay_interface = ReplayInterfaceScene.instantiate() as ReplayInterface
		replay_interface.replay = self
		Quack.root.add_child(replay_interface)
	else:
		Quack.tree.scene_changed.disconnect(replay_interface.queue_free)
	Quack.change_scene(scene_path)
	Quack.Tickrate.set_physics_simulation_rate(tickrate)
	await Quack.tree.scene_changed
	Quack.tree.scene_changed.connect(replay_interface.queue_free)
	#Quack.tree.physics_frame.connect(decode_frame)

func decode_relative_frame(idx: int) -> bool:
	idx = clampi(current_frame_idx+idx,0,size-1)
	decode_frame(idx)
	return true

# NOTE what with the amount that decoding_blocked is used in the replay interface
# theres almost a point where its not even needed to be checked in this function,
# so maybe investigate getting rid of the check
var decoding_blocked: bool = false
var current_frame_idx: int = 0
func decode_frame(idx: int) -> void:
	if decoding_blocked:
		return
	decoding_blocked = true
	var frame := frames[idx]
	if frame == null: # Frame has not yet been decoded
		if idx == 0: # First frame, so theres no in-betweens that need to be decoded.
			decode_delta(0)
			current_frame_idx = 0
			decoding_blocked = false
			return
		
		# Iterate back through frames until either the index of the most recently
		# decoded frame is found, or the first frame is hit, and everything needs
		# to be decoded lmao
		# NOTE / TODO maybe cache the most recently decoded frame
		var prev_idx: int = idx - 1
		var prev_frame: Frame = frames[prev_idx]
		if prev_frame == null:
			while prev_frame == null and prev_idx != 0:
				prev_idx -= 1
				prev_frame = frames[prev_idx]
			
			# Decode frames up until current frame
			for i in range(prev_idx,idx):
				decode_delta(i,frames[i])
		
		decode_delta(idx,frames[idx-1])
		current_frame_idx = idx
		decoding_blocked = false
		return
	else:
		frame.restore(Quack.get_current_scene())
		current_frame_idx = idx
		decoding_blocked = false
		return

func decode_delta(frame_num: int, prev_frame: Frame = Frame.new([],0)) -> void:
	var encoded := encoded_frames[frame_num]
	var frame := Frame.new([],frame_num)
	decode_encoded_frame(frame,encoded,frame_num,prev_frame)
	# These are now duplicated up front in decode_encoded_frame
	#for uid in frame.serializations:
		#frame.serializations[uid] = frame.serializations[uid].duplicate() # LMFAO
	frames[frame_num] = frame

static var serialized_node_collections: Dictionary[int,SerializedNodeCollection]

func decode_encoded_frame(frame: Frame, delta: PackedByteArray, frame_num: int, prev_frame: Frame) -> void:
	var max_bool_idx := delta.decode_u32(0)
	var buffer := StreamPeerBitBuffer.decode(delta)
	var idx: int = 0
	var hostility_mask := buffer.get_u64() if receiver_id != 0 else 0xFFFFFFFFFFFFFFF
	for uid in prev_frame.serializations:
		frame.serializations[uid] = prev_frame.serializations[uid].duplicate()
	var collections := Array(frame.serializations.values(),TYPE_OBJECT,&"RefCounted",SerializedNodeCollection) as Array[SerializedNodeCollection]
	
	while buffer.bool_position < max_bool_idx:
		
		if buffer.get_bool(): # Updated
			if buffer.get_bool(): # Delta
				var collection := collections[idx]
				var vis_type := Property.get_visibility(collection.owner_id,collection.team,receiver_id,hostility_mask)
				collection.decode_delta(buffer, vis_type)
				idx += 1
				#Console.write("%s-->%s Delta updating %s (%s), index increasing to %s."%[
				#delta_frame_num,frame_num,serializers[idx-1].uid,serializers[idx-1].owner.name,idx
				#])
			else: # Not delta
				if buffer.get_bool(): # Spawned
					var uid := buffer.get_u32()
					var scene_id := buffer.get_u8()
					#assert(not frame.serializations.has(uid),"Serializations should not have uid %s."%uid)
					var collection: SerializedNodeCollection
					if not serialized_node_collections.has(scene_id):
						# Find the correct scene by finding the path from its scene ID, then mapping that
						# path to the game's scenes through the QuackMultiplayer scene registry
						serialized_node_collections[scene_id] = Serializer.get_serialization_info(
							# The actual PackedScene
							QuackMultiplayer.scenes[
								# This scene's actual ID, by finding it thru the QuackMultiplayer scene registry
								QuackMultiplayer.scene_registry[
									# Scene path based on this replay's scene ID
									scene_registry[scene_id]
								]
							],
							scene_id)
					collection = serialized_node_collections[scene_id].duplicate()
					collection.uid = uid
					assert(collection.scene_id == scene_id)
					collection.frame_created = frame_num
					collection.owner_id = 0
					collection.team = 0
					frame.serializations[uid] = collection
					collection.decode_spawn(buffer,Property.VisibilityType.OWNER_ONLY)
				else: # Deleted
					var uid := buffer.get_u32()
					frame.serializations.erase(uid)
					idx += 1
		else:
			idx += 1

signal finished
func stop() -> void:
	#Quack.tree.physics_frame.disconnect(decode_frame)
	Network.reset()
	finished.emit()

#endregion
