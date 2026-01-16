extends Control

const Replay = preload("res://network/multiplayer/replays.gd")

@onready var first_frame := $PlaybackButtonsContainer/FirstFrame as Button
@onready var go_back := $PlaybackButtonsContainer/GoBack as Button
@onready var prev_frame := $PlaybackButtonsContainer/PrevFrame as Button
@onready var pause_button := $PlaybackButtonsContainer/PauseButton as Button
@onready var next_frame := $PlaybackButtonsContainer/NextFrame as Button
@onready var go_forward := $PlaybackButtonsContainer/GoForward as Button
@onready var last_frame := $PlaybackButtonsContainer/LastFrame as Button

var replay: Replay

var skip_time: float = 5.
@warning_ignore("narrowing_conversion")
@onready var skip_frames: int = replay.tickrate * skip_time

func go_to_frame(idx: int) -> void:
	replay.decode_frame(idx)

func _physics_process(delta: float) -> void:
	if pause_button.button_pressed:
		var scene := Quack.get_current_scene()
		if not replay.decoding_blocked and not is_queued_for_deletion() and not (scene == null or scene.is_queued_for_deletion()):
			replay.decode_relative_frame(1)

func go_to_last_frame() -> void:
	replay.decode_frame(replay.size-1)

func skip(forward: bool, frames: int = skip_frames) -> void:
	replay.decode_relative_frame(frames if forward else -frames)

func _ready() -> void:
	for i in 2:
		await Quack.tree.process_frame
	Quack.get_current_scene().process_mode = PROCESS_MODE_DISABLED
