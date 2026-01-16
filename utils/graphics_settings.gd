const GRAPHICS_SETTING_PATH = "quack/graphics/"
const ENVIRONMENT_SETTING_PATH = GRAPHICS_SETTING_PATH+"environment/"
const ENVIRONMENT_OVERRIDES_SETTING_PATH = "overrides/overrideable_settings"
const environment_overrides: PackedStringArray = ["quack/graphics/environment/glow/enabled", "quack/graphics/environment/ssr/enabled", "quack/graphics/environment/ssao/enabled", "quack/graphics/environment/ssil/enabled", "quack/graphics/environment/sdfgi/enabled", "quack/graphics/environment/fog/enabled", "quack/graphics/environment/volumetric_fog/enabled", "quack/graphics/environment/adjustments/enabled", "quack/graphics/environment/reflected_light/source"]

static func apply_environment_settings() -> void:
	var env := Quack.root.world_3d.environment
	if !env: return
	var var_name: String
	for setting:String in ProjectSettings.get_setting_safe(ENVIRONMENT_OVERRIDES_SETTING_PATH,environment_overrides):
		# replacing adjustments with adjustment is a HACK lmao
		var_name = environment_setting_to_var_name(setting).replacen("adjustments","adjustment")
		env[var_name] = ProjectSettings.get_setting_safe(
			setting,
			ClassDB.class_get_property_default_value(&"Environment",var_name)
		)
		Console.writeverb("Applying setting %s to environment as %s."%[setting,var_name])

static func environment_setting_to_var_name(setting: String) -> String:
	return setting.trim_prefix(ENVIRONMENT_SETTING_PATH).replacen("/","_")
