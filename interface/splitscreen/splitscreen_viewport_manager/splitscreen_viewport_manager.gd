extends HFlowContainer

const Splitscreen = preload("res://interface/splitscreen/splitscreen.gd")

@warning_ignore_start("narrowing_conversion")

func _ready() -> void:
	resize_to_root()

func _enter_tree() -> void:
	Quack.root.size_changed.connect(resize_to_root)
func _exit_tree() -> void:
	Quack.root.size_changed.disconnect(resize_to_root)

func resize_to_root() -> void:
	size = Quack.root.size
	var viewports := Splitscreen.sub_viewports
	var num_vps := viewports.size()
	
	match num_vps:
		1:
			viewports[0].size = size
		2:
			if Splitscreen.get_prefer_wider_viewports():
				for viewport in viewports:
					viewport.size = Vector2i(size.x,size.y/2)
			else:
				for viewport in viewports:
					viewport.size = Vector2i(size.x/2,size.y)
		3:
			var preferred_player_idx := clampi(Splitscreen.get_odd_num_viewports_preferred_player_num(),0,2)
			var prefer_wider_vps := Splitscreen.get_prefer_wider_viewports()
			var preferred_player_gets_preferred_style := Splitscreen.get_preferred_player_gets_preferred_viewport_style()
			var main_size := Vector2i(size.x,size.y/2) if prefer_wider_vps else Vector2i(size.x/2,size.y)
			var alt_size := Vector2i(size/2)
			for i in num_vps:
				if i == preferred_player_idx:
					# NOTE BUG THIS LINE IS WRONG
					viewports[i].size = main_size if preferred_player_gets_preferred_style else alt_size
				else:
					pass
					#viewports[i].size = 
		4:
			for viewport in viewports:
				viewport.size = Vector2i(size.x/2,size.y/2)
		5:
			if Splitscreen.get_prefer_wider_viewports():
				pass
			else:
				pass
		6:
			if Splitscreen.get_prefer_wider_viewports():
				for viewport in viewports:
					viewport.size = Vector2i(size.x/2,size.y/3)
			else:
				for viewport in viewports:
					viewport.size = Vector2i(size.x/3,size.y/2)
		7:
			if Splitscreen.get_prefer_wider_viewports():
				pass
			else:
				pass
		8:
			if Splitscreen.get_prefer_wider_viewports():
				for viewport in viewports:
					viewport.size = Vector2i(size.x/2,size.y/4)
			else:
				for viewport in viewports:
					viewport.size = Vector2i(size.x/4,size.y/2)
		_:
			# Might be incorrect if its intended for every player to be able to pop out a window
			Console.get_assertfail_msg(false,"%s is an invalid number of splitscreen subviewports! Must be from 1-8"%num_vps,true)
	
	## Even num viewports
	#if num_vps % 2 == 0:
		#if num_vps == 4:
			#pass
		#elif num_vps 
	## Odd num viewports
	#else:
		#var prefer_wider_viewports := Splitscreen.get_prefer_wider_viewports()
		#var preferred_player_num := Splitscreen.get_prefer_wider_viewports()
	##for viewport in viewports:
		##viewport.size = 
