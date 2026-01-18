@tool
extends EditorScript

const hitbox_parent_path = ^"."
const nodepath := ^"BodyModel/TPSkeleton"
const Hitbox = preload("res://gameplay/hitbox.gd")

const exclusions: PackedStringArray = ["mvm","root","body"]
const prefix_exclusions: PackedStringArray = ["prp_"]
const suffix_exclusions: PackedStringArray = []
const text_exclusions: PackedStringArray = ["collar","weapon","thumb","index","middle","ring","pinky","toe",'hip']
const inclusions: PackedStringArray = []

func _run() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	
	if scene_root.has_node(nodepath):
		var skelly := scene_root.get_node(nodepath)
		if skelly is Skeleton3D:
			var hitbox_parent := scene_root.get_node(hitbox_parent_path)
			if hitbox_parent:
				make_hitboxes(scene_root, skelly as Skeleton3D, hitbox_parent)
			else:
				printerr("Scene does not have a node at path %s!"%hitbox_parent_path)
		else:
			printerr("Skeleton %s is not a Skeleton3D!"%skelly)
	else:
		printerr("Scene does not have a node at path %s!"%nodepath)


func make_hitboxes(root: Node, skeleton: Skeleton3D, hitbox_parent: Node) -> void:
	var shape_map: Dictionary[float,SphereShape3D]
	for bone in skeleton.get_bone_count():
		var bone_name: String = skeleton.get_bone_name(bone)
		var lower := bone_name.to_lower()
		if not inclusions.is_empty():
			if not lower in inclusions:
				print("Skipping bone %s for not being included."%bone_name)
				continue
		if lower in exclusions:
			print("Skipping excluded bone %s."%bone_name)
			continue
		var skip: bool = false
		for prefix in prefix_exclusions:
			if lower.begins_with(prefix):
				print("Skipping excluded bone %s for starting with %s."%[bone_name,prefix])
				skip = true; break
		if skip: continue
		for suffix in suffix_exclusions:
			if lower.ends_with(suffix):
				print("Skipping excluded bone %s for ending with %s."%[bone_name,suffix])
				skip = true; break
		if skip: continue
		for text in text_exclusions:
			if text in lower:
				print("Skipping excluded bone %s for having excluded text %s."%[bone_name,text])
				skip = true; break
		if skip: continue
		
		var bone_transform := skeleton.get_bone_global_rest(bone)
		var kids := skeleton.get_bone_children(bone)
		var mapped: MappedHitbox
		if kids.is_empty():
			print("Bone %s has no children, and thus its size cannot be found."%bone_name)
			continue
		else:
			var max_dist: float
			var name: String
			for child in kids:
				var transform := skeleton.get_bone_global_rest(child)
				var dist := bone_transform.origin.distance_to(transform.origin)
				if dist > max_dist:
					max_dist = dist
					name = skeleton.get_bone_name(child)
			print("Making hitbox from %s to %s."%[bone_name,name])
			max_dist = snappedf(max_dist,.001)
			if max_dist == 0.:
				printerr("Max dist must be greater than 0 to create a hitbox.")
				continue
			mapped = MappedHitbox.new()
			if shape_map.has(max_dist):
				print("Max dist %s already exists. Grabbing shape from map."%max_dist)
				mapped.shape.shape = shape_map[max_dist]
			else:
				print("New max dist %s. Adding to map."%max_dist)
				var shape := SphereShape3D.new()
				shape.radius = max_dist
				mapped.shape.shape = shape
				shape_map[max_dist] = shape
		
		var hitbox_name := (bone_name+"Hitbox").to_pascal_case()
		var attachment_name := (bone_name+"Bone").to_pascal_case()
		
		mapped.boneattachment.name = attachment_name
		mapped.hitbox.name = hitbox_name
		
		skeleton.add_child(mapped.boneattachment,true)
		mapped.boneattachment.set_bone_name(bone_name)
		
		hitbox_parent.add_child(mapped.hitbox,true)
		mapped.assign_transformer_path()
		mapped.hitbox.set_owner(root)
		mapped.boneattachment.set_owner(root)
		mapped.transformer.set_owner(root)
		mapped.shape.set_owner(root)

class MappedHitbox:
	var hitbox := Hitbox.new()
	var boneattachment := BoneAttachment3D.new()
	var transformer := RemoteTransform3D.new()
	var shape := CollisionShape3D.new()
	
	func assign_transformer_path() -> void:
		transformer.set_remote_node(transformer.get_path_to(hitbox))
	
	func _init() -> void:
		
		hitbox.collision_mask = 0
		hitbox.collision_layer = Hitbox.Collision.Layer.HITBOX
		
		transformer.update_scale = false
		
		shape.debug_color = Color("e600c36b")
		shape.name = &"Shape"
		transformer.name = &"Transformer"
		
		hitbox.add_child(shape,true)
		boneattachment.add_child(transformer,true)
