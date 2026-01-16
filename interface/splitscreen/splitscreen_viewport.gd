const QuackPlayer = preload("res://network/multiplayer/player.gd")
const Splitscreen = preload("res://interface/splitscreen/splitscreen.gd")
const SplitscreenViewport = preload('res://interface/splitscreen/splitscreen_viewport.gd')
const SplitscreenContainer = preload("res://interface/splitscreen/splitscreen_container.tscn")
const SplitscreenMode = Splitscreen.SplitscreenMode

var player: QuackPlayer
var viewport: Viewport
var mode: SplitscreenMode

func _init(player: QuackPlayer, viewport: Viewport) -> void:
	self.player = player
	self.viewport = viewport
	if viewport is SubViewport:
		mode = SplitscreenMode.SUB_VIEWPORT
	else:
		assert(viewport is Window, "The only alternative to a sub viewport should be a window, but this viewport is a %s."%viewport)
		mode = SplitscreenMode.SEPARATE_WINDOW

static func create_splitscreen_viewport(player: QuackPlayer) -> SplitscreenViewport:
	var viewport := SplitscreenContainer.instantiate().get_child(0) as SubViewport
	Splitscreen.sub_viewports.append(viewport)
	return SplitscreenViewport.new(player,viewport)

static func create_window(player: QuackPlayer) -> SplitscreenViewport:
	var window := Window.new()
	window.force_native = true
	Splitscreen.windows.append(window)
	return SplitscreenViewport.new(player,window)
