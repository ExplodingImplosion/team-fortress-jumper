const color_wrapper: String = "[color=%s]%s[/color]"
static func add_bbcode(s: String, color: String) -> String:
	return color_wrapper%[color,s]

static func set_color(s: String, color: Color) -> String:
	return add_bbcode(s,color.to_html(false))

static func set_color_by_type(variant: Variant) -> String:
	return set_color(str(variant),get_type_color(typeof(variant)))

static func set_color_by_type_pretty(variant: Variant) -> String:
	return set_color(var_to_str(variant),get_type_color(typeof(variant)))

static func set_color_by_type_nested(variant: Variant, multi_line: bool = false) -> String:
	var type := typeof(variant)
	match type:
		TYPE_ARRAY:
			var string := set_color("[" if multi_line else "\t]",get_type_color(TYPE_DICTIONARY))
			for i in (variant as Array):
				string += ("\n%s," if multi_line else "	%s,")%set_color_by_type_nested(i, multi_line)
			string += set_color("\n]" if multi_line else "\t]",get_type_color(TYPE_DICTIONARY))
			return string
		TYPE_DICTIONARY:
			var string := set_color("{" if multi_line else "{\t",get_type_color(TYPE_DICTIONARY))
			for i in (variant as Dictionary):
				string += ("\n%s:	%s" if multi_line else "%s:	%s,	")%[
					set_color_by_type_nested(i, multi_line),
					set_color_by_type_nested((variant as Dictionary)[i], multi_line)
				]
			string += set_color("\n}" if multi_line else "\t}",get_type_color(TYPE_DICTIONARY))
			return string
		_:
			return set_color(str(variant),get_type_color(type))

static func get_type_color(type: Variant.Type) -> Color:
	match type:
		TYPE_BOOL:
			return Color.ORANGE
		TYPE_STRING:
			return Color.YELLOW
		TYPE_STRING_NAME:
			return Color.BURLYWOOD
		TYPE_INT:
			return Color.LIGHT_SEA_GREEN
		TYPE_FLOAT:
			return Color.CORAL
		TYPE_VECTOR2:
			return Color.LIGHT_BLUE
		TYPE_VECTOR2I:
			return Color.CYAN
		TYPE_VECTOR3:
			return Color.GREEN
		TYPE_VECTOR3I:
			return Color.GREEN_YELLOW
		TYPE_PACKED_INT64_ARRAY:
			return Color.SEA_GREEN
		TYPE_PACKED_BYTE_ARRAY:
			return  Color.MEDIUM_SPRING_GREEN
		TYPE_DICTIONARY:
			return Color.BISQUE
		TYPE_OBJECT:
			return Color.MEDIUM_SEA_GREEN
		_:
			return Color.MAGENTA
