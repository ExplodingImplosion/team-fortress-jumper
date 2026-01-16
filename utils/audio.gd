const MASTER_VOLUME_SETTING = "quack/audio/volume/master_volume"

# Maybe make this a static var? idk it probably doesnt matter. but would this
# bus ever get reordered? who knows lmao
static func get_master_volume_bus_idx() -> int:
	return AudioServer.get_bus_index(&"Master")

static func set_volume(volume: float) -> void:
	AudioServer.set_bus_volume_linear(get_master_volume_bus_idx(),volume)
	ProjectSettings.set_setting(MASTER_VOLUME_SETTING,volume)

static func get_volume() -> float:
	return ProjectSettings.get_setting_safe(MASTER_VOLUME_SETTING,1.) as float
