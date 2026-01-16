extends FlowContainer

const Splitscreen = preload("res://interface/splitscreen/splitscreen.gd")

@warning_ignore_start("narrowing_conversion")

var num_viewports: int
var viewports: Array[SubViewport]
#var sizes: PackedVector2Array
var crosshairs: Array[ColorRect]
var ratios: PackedVector2Array

func fill_viewports() -> void:
	var node: Node
	for child:SubViewportContainer in get_children():
		if child.get_child_count() > 0:
			node = child.get_child(0)
			if node is SubViewport:
				viewports.append(node as SubViewport)
				var rect := ColorRect.new()
				Quack.add_child(rect)
				rect.size = Vector2(2,2)
				crosshairs.append(rect)
				# lmfao
				if Console.console_commands_script.perf_overlay:
					Console.console_commands_script.perf_overlay.add_viewport(node as SubViewport)
	num_viewports = viewports.size()

const editor_res = Vector2(1152,648) # intentionally not a vector2i for fracs
func fill_ratios() -> void:
	ratios.resize(num_viewports)
	#sizes.resize(num_viewports)
	for i in num_viewports:
		ratios[i] = Vector2(viewports[i].size) / editor_res
		#sizes[i] = Vector2(viewports[i].size)

func _ready() -> void:
	fill_viewports()
	fill_ratios()
	resize_to_root.call_deferred()

func _enter_tree() -> void:
	Quack.root.size_changed.connect(resize_to_root)
func _exit_tree() -> void:
	Quack.root.size_changed.disconnect(resize_to_root)
	# This is intentional cuz crosshairs are children of Quack and not the viewport
	# manager.
	for crosshair in crosshairs:
		crosshair.queue_free()

func realign_crosshair(idx: int) -> void:
	var crosshair := crosshairs[idx]
	var vp_pos := (viewports[idx].get_parent() as Control).position
	crosshair.position = vp_pos + (Vector2(viewports[idx].size) / 2) - Vector2(1,1)

func resize_to_root() -> void:
	#for i in 3:
		#await Quack.tree.process_frame
	#size = Quack.root.size
	var root_size := Vector2(Quack.root.size)
	for i in num_viewports:
		viewports[i].size = root_size * ratios[i]
		realign_crosshair.call_deferred(i)
