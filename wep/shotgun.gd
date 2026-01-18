extends WeaponNode

func _ready() -> void:
	owner.ready.connect(setup_hitbox_exceptions)

func setup_hitbox_exceptions() -> void:
	if Hitbox.hitbox_owners.has(owner):
		var hitboxes := Hitbox.hitbox_owners[owner] as Array[Hitbox]
		var num_hitboxes := hitboxes.size()
		hitbox_exceptions.resize(num_hitboxes)
		for i in num_hitboxes:
			hitbox_exceptions[i] = hitboxes[i].get_rid()
	# This means it also includes your own bounding box hehe lmao
	if bb:
		hitbox_exceptions.append(bb.get_rid())

var hitbox_exceptions: Array[RID]

const Collision = preload("res://gameplay/collision.gd")
const Hitbox = preload("res://gameplay/hitbox.gd")
const BULLET_LAYER = Collision.Layer.HITBOX | Collision.Layer.SOLID_GEO
const BULLET_SPREAD_DISTANCE_FROM_CENTER := deg_to_rad(3)
const BULLET_SPREAD_BASE_OFFSETS: Array[Vector2] = [
	Vector2( 0.0,  0.0),
	
	Vector2(-1.0, -1.0) * BULLET_SPREAD_DISTANCE_FROM_CENTER,
	Vector2( 0.0, -1.0) * BULLET_SPREAD_DISTANCE_FROM_CENTER,
	Vector2( 1.0, -1.0) * BULLET_SPREAD_DISTANCE_FROM_CENTER,
	
	Vector2(-1.0,  0.0) * BULLET_SPREAD_DISTANCE_FROM_CENTER,
	Vector2( 0.0,  0.0) * BULLET_SPREAD_DISTANCE_FROM_CENTER,
	Vector2( 1.0,  0.0) * BULLET_SPREAD_DISTANCE_FROM_CENTER,
	
	Vector2(-1.0,  1.0) * BULLET_SPREAD_DISTANCE_FROM_CENTER,
	Vector2( 0.0,  1.0) * BULLET_SPREAD_DISTANCE_FROM_CENTER,
	Vector2( 1.0,  1.0) * BULLET_SPREAD_DISTANCE_FROM_CENTER, 
]

@export var inaccuracy := deg_to_rad(1.0) # Not really measured, based on a guess.

@export_range(0, 120, 1, "hide_slider", "or_greater")
var base_damage := 6.0

@export var bullet_trail: GPUParticles3D
@export var bb: BoundingBox

func _deploy():
	const DEPLOY_ANIMATIONS = [
		&"shotgun_draw_pump", &"shotgun_draw_no_pump", &"shotgun_draw_lastshot_reload"
	]
	first_person_player.play(DEPLOY_ANIMATIONS.pick_random())
	if not first_person_player.animation_finished.is_connected(_on_FirstPersonPlayer_animation_finished):
		first_person_player.animation_finished.connect(_on_FirstPersonPlayer_animation_finished)

const HitResolver = preload("res://network/multiplayer/hit_resolver.gd")
const OwnerID = Quack.Network.OwnerID
const BoundingBox = HitResolver.BoundingBox

func _shoot():
	const SHOOT_ANIMATIONS = [&"shotgun_fire", &"shotgun_fire_nopump"]
	shoot_sfx.play()
	first_person_player.stop()
	first_person_player.play(SHOOT_ANIMATIONS.pick_random())
	
	for i in BULLET_SPREAD_BASE_OFFSETS.size():
		if HitResolver.is_valid_hit_resolution_subject(player_owner):
			HitResolver.hit_resolver.request_hit(
				OwnerID.get_node_owner_id(player_owner),
				self,
				_create_bullet.bind(BULLET_SPREAD_BASE_OFFSETS[i], i == 0),
				BoundingBox.get_ray_intersection_intersections(
					get_world_3d(),
					get_raycast_query(BULLET_SPREAD_BASE_OFFSETS[i], i == 0)
				)
			)
		else:
			_create_bullet(BULLET_SPREAD_BASE_OFFSETS[i], i == 0)

func get_raycast_query(base_offset := Vector2.ZERO, first_bullet := false) -> PhysicsRayQueryParameters3D:
	var spread := Vector2.ZERO if first_bullet else Vector2(
			randfn(0, inaccuracy), 
			randfn(0, inaccuracy))
	var ahead := -global_transform.basis.z.rotated(
			global_transform.basis.y, base_offset.y + spread.y).rotated(
			global_transform.basis.x, base_offset.x + spread.x)
	
	var from := global_position
	var to := from + (ahead * 10000 * HU)
	return PhysicsRayQueryParameters3D.create(from, to, BULLET_LAYER,hitbox_exceptions)

func _create_bullet(base_offset := Vector2.ZERO, first_bullet := false):
	
	var spread := Vector2.ZERO if first_bullet else Vector2(
			randfn(0, inaccuracy), 
			randfn(0, inaccuracy))
	var ahead := -global_transform.basis.z.rotated(
			global_transform.basis.y, base_offset.y + spread.y).rotated(
			global_transform.basis.x, base_offset.x + spread.x)
	
	var from := global_position
	var to := from + (ahead * 10000 * HU)
	var query := PhysicsRayQueryParameters3D.create(from, to, BULLET_LAYER, hitbox_exceptions)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	
	var hit_point := to
	if result:
		hit_point = result.position
		var play_bullet_inpact_sfx = func(bullet_impact: AudioStreamPlayer3D):
			if first_bullet:
				bullet_impact.global_position = hit_point
				bullet_impact.play()
		
		if result.collider is Hitbox:
			result.collider = (result.collider as Hitbox).owner
		
		if result.collider is Player:
			deal_damage(result.collider)
			play_bullet_inpact_sfx.call($BulletImpactFlesh)
		else:
			add_decal(preload("./other/BulletDecal.tscn"), hit_point, result.normal)
			play_bullet_inpact_sfx.call($BulletImpact)
		if BoundingBox.can_show_hitreg():
			Quack.spawn_recolored_debug_mesh(Quack.impact_mesh,Color(1,0,0,.5),Transform3D(Basis.IDENTITY,hit_point),10.)
	
	var particle_origin := bullet_trail.global_position
	
	bullet_trail.emit_particle(bullet_trail.global_transform,
			bullet_trail.to_local(particle_origin).direction_to(bullet_trail.to_local(hit_point)) * max(particle_origin.distance_to(hit_point) * 2, 20),
			Color.WHITE, Color(),
			GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY)

func deal_damage(player: Player):
	var damage := base_damage
	damage *= get_damage_falloff(player_owner.global_position.distance_to(player.global_position))
	player.take_damage(damage, player_owner)
	
	var multiplier := 0.05#0.2
	var direction := (global_position + Vector3(0, -10 * HU, 0)).direction_to(player.global_position)
	var volume_ratio := 1.49091 if player.crouched else 1.0
	var knockback_force := minf(damage * volume_ratio * multiplier, 1000 * HU)
	var add_velocity := knockback_force * direction
	player.velocity += add_velocity


static func get_damage_falloff(distance: float) -> float:
	var unit := clampf(remap(distance, 0.0, 1024 * HU, 0.0, 1.0), 0.0, 1.0)
	
	return cubic_interpolate(1.5, 0.5, 0.0, 0.0, unit)


func _on_FirstPersonPlayer_animation_finished(anim_name: StringName) -> void:
	# Mostly a cute, accurate reloading test.
	if anim_name == &"shotgun_draw_lastshot_reload":
		first_person_player.play(&"shotgun_reload_start")
		first_person_player.queue(&"shotgun_reload")
		create_tween().tween_interval(3).finished.connect(
				first_person_player.play.bind(&"shotgun_reload_end"))
