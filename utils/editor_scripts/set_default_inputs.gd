@tool
extends EditorScript

const defaults_filepath = "res://utils/default_input_profile.tres"

func _run() -> void:
	var defaults: InputProfile = load(defaults_filepath)
	for property in ProjectSettings.get_property_list():
		var name := property.name as String
		var action := name.get_file()
		if name.begins_with("input/") and not action.begins_with("ui_"):
			var info := ProjectSettings.get_setting(name,{}) as Dictionary
			prints(action,info)
			var input_action := InputAction.new()
			input_action.action = action
			input_action.deadzone = info.deadzone as float
			for event in info.events:
				input_action.events.append(event)
			defaults.actions[action] = input_action
	var err := ResourceSaver.save(defaults,defaults_filepath)
	print(error_string(err))
