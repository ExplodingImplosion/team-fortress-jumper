enum LayerIndex {
	SOLID_GEO,
	#PLAYER_COLLISION,
	#DAMAGE,
	#KNOCKBACK,
	#INTERACTION,
	#AIM_ASSIST,
	NETWORK = 6,
	#PROPS,
	PLAYERS = 8,
	PROJECTILES,
	HITBOX,
}

enum Layer {
	SOLID_GEO = 1<<LayerIndex.SOLID_GEO,
	#PLAYER_COLLISION = 1<<LayerIndex.PLAYER_COLLISION,
	#DAMAGE = 1<<LayerIndex.DAMAGE,
	#KNOCKBACK = 1<<LayerIndex.KNOCKBACK,
	#INTERACTION = 1<<LayerIndex.INTERACTION,
	#AIM_ASSIST = 1<<LayerIndex.AIM_ASSIST,
	NETWORK = 1<<LayerIndex.NETWORK,
	#PROPS = 1<<LayerIndex.PROPS,
	PLAYERS = 1<<LayerIndex.PLAYERS,
	PROJECTILES = 1<<LayerIndex.PROJECTILES,
	HITBOX = 1<<LayerIndex.HITBOX,
}

static func is_in_layer(layers: int, layer: Layer) -> bool:
	return bool(layers&layer)

static func scale_shape(shape: Shape3D, scale: float) -> void:
	match shape.get_class():
		"BoxShape3D":
			var typed := (shape as BoxShape3D)
			typed.size *= scale
		"CapsuleShape3D":
			var typed := (shape as CapsuleShape3D)
			typed.height *= scale
			typed.radius *= scale
		"ConcavePolygonShape3D":
			Console.push_err("Scaling ConcavePolygonShape3D is not currently supported!")
			#var typed := (shape as ConcavePolygonShape3D)
			#typed
		"ConvexPolygonShape3D":
			Console.push_err("Scaling ConvexPolygonShape3D is not currently supported!")
			#var typed := (shape as ConvexPolygonShape3D)
			#typed
		"CylinderShape3D":
			var typed := (shape as CylinderShape3D)
			typed.height *= scale
			typed.radius *= scale
		"HeightMapShape3D":
			Console.push_err("Scaling HeightMapShape3D is not currently supported!")
			#var typed := (shape as HeightMapShape3D)
			#typed
		"SeparationRayShape3D":
			var typed := (shape as SeparationRayShape3D)
			typed.length *= scale
		"SphereShape3D":
			var typed := (shape as SphereShape3D)
			typed.radius *= scale
		"WorldBoundaryShape3D":
			Console.push_err("Scaling WorldBoundaryShape3D is not currently supported!")
			#var typed := (shape as WorldBoundaryShape3D)
			#typed
		_:
			Console.push_err("Invalid shape type %s!"%shape.get_class())

static func get_shape_extents(shape: Shape3D) -> Vector3:
	match shape.get_class():
		"BoxShape3D":
			var typed := (shape as BoxShape3D)
			return typed.size
		"CapsuleShape3D":
			var typed := (shape as CapsuleShape3D)
			var diameter := typed.radius*2
			return Vector3(diameter,typed.height,diameter)
		"ConcavePolygonShape3D":
			Console.push_err("Scaling ConcavePolygonShape3D is not currently supported!")
			#var typed := (shape as ConcavePolygonShape3D)
			#typed
			return Vector3.ZERO
		"ConvexPolygonShape3D":
			Console.push_err("Scaling ConvexPolygonShape3D is not currently supported!")
			#var typed := (shape as ConvexPolygonShape3D)
			#typed
			return Vector3.ZERO
		"CylinderShape3D":
			var typed := (shape as CylinderShape3D)
			var diameter := typed.radius*2
			return Vector3(diameter,typed.height,diameter)
		"HeightMapShape3D":
			Console.push_err("Scaling HeightMapShape3D is not currently supported!")
			#var typed := (shape as HeightMapShape3D)
			#typed
			return Vector3.ZERO
		"SeparationRayShape3D":
			var typed := (shape as SeparationRayShape3D)
			return Vector3(0,typed.length,0)
		"SphereShape3D":
			var typed := (shape as SphereShape3D)
			var diameter := typed.radius*2
			return Vector3(diameter,diameter,diameter)
		"WorldBoundaryShape3D":
			Console.push_err("Scaling WorldBoundaryShape3D is not currently supported!")
			#var typed := (shape as WorldBoundaryShape3D)
			#typed
			return Vector3.ZERO
		_:
			Console.push_err("Invalid shape type %s!"%shape.get_class())
			return Vector3.ZERO

static func get_center_of_mass(object: CollisionObject3D) -> Vector3:
	return PhysicsServer3D.body_get_direct_state(object.get_rid()).center_of_mass
