extends Node

const Network = preload("res://network/network.gd")
const HitResolver = preload("res://network/multiplayer/hit_resolver.gd")
const Hitbox = preload("res://gameplay/hitbox.gd")

const MultiplayerLevel = preload("res://gameplay/level/common/multiplayer_level.gd")
const MultiplayerSession = MultiplayerLevel.MultiplayerSession
const BoundingBox = MultiplayerLevel.BoundingBox
const PhysicsPriority = MultiplayerLevel.PhysicsPriority
const Serializer = MultiplayerLevel.Serializer

static var hit_resolver: HitResolver

static func is_valid_hit_resolution_subject(node: Node) -> bool:
	return hit_resolver and Network.is_node_remote(node)

var mp_level: MultiplayerLevel
var hit_requests: Array[HitRequest]
var hit_map: Dictionary[int,HitRequest]

func _init(mp_level: MultiplayerLevel) -> void:
	assert(not hit_resolver,"Hit resolver %s already exists!"%hit_resolver)
	process_physics_priority = PhysicsPriority.HIT_RESOLVER
	hit_resolver = self
	self.mp_level = mp_level

func _exit_tree() -> void:
	hit_resolver = null

func _physics_process(_delta: float) -> void:
	resolve_hits.call_deferred()

func resolve_hits() -> void:
	for request in hit_requests:
		request.resolve(mp_level)
	hit_requests.clear()
	hit_map.clear()

func request_hit(player_id: int, requester: Node, callable: Callable, bounding_boxes: Array[BoundingBox]) -> void:
	if bounding_boxes.is_empty():
		callable.call()
		return
	if hit_map.has(player_id):
		var request := hit_map[player_id]
		request.merge(requester,callable,bounding_boxes)
	else:
		var request := HitRequest.new(player_id,requester,callable,bounding_boxes)
		hit_requests.append(request)
		hit_map[player_id] = request

class HitRequest:
	var player_id: int
	var requesters: Array[Node]
	var callables: Array[Callable]
	var bounding_boxes: Dictionary[BoundingBox,Variant]
	
	func merge(requester: Node, callable: Callable, bounding_boxes: Array[BoundingBox]) -> void:
		self.requesters.append(requester)
		self.callables.append(callable)
		for box in bounding_boxes:
			self.bounding_boxes[box] = null
	
	func _init(player_id: int, requester: Node, callable: Callable, bounding_boxes: Array[BoundingBox]) -> void:
		self.player_id = player_id
		merge(requester,callable,bounding_boxes)
	
	func resolve(level: MultiplayerLevel) -> void:
		var player_inputs: Inputs.PlayerInputs
		if MultiplayerSession.players.has(player_id):
			player_inputs = MultiplayerSession.players[player_id].get_input()
		else:
			return Console.push_err("Player %s does not exist."%player_id)
		
		var frame := player_inputs.frame_hint
		var interp_frac := player_inputs.firing_interp_fraction
		#Console.write(player_id,frame,MultiplayerSession.players[player_id].client.most_recent_acked_frame.num)
		var frame_before := level.history_saver.get_frame_clamped(frame-1)
		var current_frame := level.history_saver.get_frame_clamped(frame)
		if frame_before.num == 0 or current_frame.num == 0:
			return
		if frame != current_frame.num:
			Console.writerr("Only rewinding back to %s instead of %s."%[current_frame.num,frame])
			assert(frame_before == current_frame, "rewinding clamped is broken if %s != %s"%[frame_before.num,current_frame.num])
		#else:
			#Console.write("Fired on frame %s frac %s"%[frame,interp_frac])
		var serializers: Array[Serializer]
		
		for bounding_box in bounding_boxes:
			#Console.write("bb owner",bounding_box.owner.name if bounding_box.owner else &"none")
			if bounding_box.owner:
				if Serializer.component_list.has(bounding_box.owner):
					serializers.append(Serializer.component_list[bounding_box.owner])
				else:
					Console.push_err("Bounding box %s is owned by an unserialized node %s [%s]."%[
						bounding_box,bounding_box.owner.name,bounding_box.owner
					])
			else:
				Console.push_err("Bounding box %s has no owner. parent: %s"%[bounding_box,bounding_box.get_parent()])
		
		var dirtied: Array[Serializer]
		
		for serializer in serializers:
			var show_hitreg := ProjectSettings.get_setting_safe("quack/debug/show_hitreg",false) as bool
			HitRequest.hitreg_debug_boxes(show_hitreg,serializer,Color(0,1,0,.05))
			
			# Serializer is old enough to be interpolated between 2 frames
			if serializer.serialized.frame_created <= frame_before.num and not frame_before == current_frame:
				dirtied.append(serializer)
				# If showing hitreg, then get the debug box position at wherever the physical
				# properties were when the player shot, but before everything else so that
				# interpolation doesnt get screwed up
				if show_hitreg:
					serializer.update_physical_properties(current_frame.serializations[serializer.uid].property_lists,1.,false)
					HitRequest.hitreg_debug_boxes(show_hitreg,serializer,Color(0.0, 1.0, 1.0, 0.05))
				
				# Set serializer physical properties to the values they
				# had on the frame before the player shot
				serializer.update_physical_properties(frame_before.serializations[serializer.uid].property_lists,1.,false)
				HitRequest.hitreg_debug_boxes(show_hitreg,serializer,Color(0,0,1,.05))
				assert(serializer.serialized.frame_created <= frame if frame > 0 else true, "Wtf!")
				# Set serializer physical properties to the interpolated
				# values between the frame before and the frame that the
				# player shot, to get sub-frame hitreg precision
				serializer.update_physical_properties(current_frame.serializations[serializer.uid].property_lists,interp_frac)
				HitRequest.hitreg_debug_boxes(show_hitreg,serializer,Color(1,0,1,.05))
			# Serializer was created on the same frame the player shot
			elif serializer.serialized.frame_created <= current_frame.num:
				dirtied.append(serializer)
				# Set serializer physical properties to the values they
				# had on the frame the player shot.
				serializer.update_physical_properties(current_frame.serializations[serializer.uid].property_lists)
				HitRequest.hitreg_debug_boxes(show_hitreg,serializer,Color(1,0,1,.05))
				
		
		var requester: Node
		#var callable: Callable
		assert(requesters.size() == callables.size())
		for i in requesters.size():
			requester = requesters[i]
			if requester and is_instance_valid(requester):
				callables[i].call()
			else:
				Console.push_err("Requester %s is %s."%[i,("null" if not requester else "invalid")])
		
		for serializer in dirtied:
			serializer.update_physical_properties(serializer.serialized.property_lists)

	static func hitreg_debug_boxes(show_hitreg: bool, serializer: Serializer, color: Color, time: float = 10) -> void:
		if show_hitreg:
			if serializer.owner is CollisionObject3D:
				var casted := serializer.owner as CollisionObject3D
				Quack.spawn_recolored_colldier_debug_mesh(BoundingBox.ColliderComponent.component_list[casted],color,time)
			if Hitbox.hitbox_owners.has(serializer.owner):
				for hitbox:Hitbox in Hitbox.hitbox_owners[serializer.owner]:
					Quack.spawn_colldier_debug_mesh(hitbox.get_child(0) as CollisionShape3D,time)
