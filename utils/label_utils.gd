static func disable_mouse_blocking(node: Control) -> void:
	set_mouse_filter(node,Control.MOUSE_FILTER_IGNORE)

static func set_mouse_filter(node: Control, filter: int) -> void:
	node.set(&"mouse_filter",filter)

static func set_font_color(label: Label, color: Color = Color.WHITE) -> void:
	label.set(&"theme_override_colors/font_color", color)

static func set_font(label: Label, font: Font) -> void:
	label.set(&"theme_override_fonts/font", font)

static func set_font_size(label: Label, size: int) -> void:
	label.set(&"theme_override_font_sizes/font_size",size)

static func set_font_outline_color(label: Label, color: Color = Color.BLACK) -> void:
	label.set(&"theme_override_colors/font_outline_color", color)

static func set_font_outline_size(label: Label, size: int = 1) -> void:
	label.set(&"theme_override_constants/outline_size",size)

static func remove_font_outline(label: Label) -> void:
	label.set(&"theme_override_constants/outline_size",0)
#	set_font_outline_size(label, 0)

static func set_font_shadow_color(label: Label, color: Color = Color.DARK_GRAY) -> void:
	label.set(&"theme_override_colors/font_shadow_color", color)

static func remove_font_shadow(label: Label) -> void:
	label.set(&"theme_override_colors/font_shadow_color",null)

static func set_font_shadow_offset(label: Label, offset: Vector2 = Vector2.ZERO) -> void:
	label.set(&"theme_override_constants/shadow_offset_x",offset.x)
	label.set(&"theme_override_constants/shadow_offset_y",offset.y)

static func set_font_shadow_outline_size(label: Label, size: float) -> void:
	label.set(&"theme_override_constants/shadow_outline_size",size)

static func remove_font_shadow_outline(label: Label) -> void:
	label.set(&"theme_override_constants/shadow_outline_size",0.)

static func add_label_pair(parent: Node = null, separation: int = -1) -> HBoxContainer:
	return add_children_of_hbox(Label.new(),Label.new(),parent,separation)

static func add_label_and_vbox(parent: Node = null, separation: int = -1) -> HBoxContainer:
	return add_children_of_hbox(Label.new(),VBoxContainer.new(),parent,separation)

static func add_children_of_hbox(left: Control, right: Control, parent: Node = null, separation: int = -1) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	if separation > -1:
		hbox.separation = separation
	if parent:
		parent.add_child(hbox)
	hbox.add_child(left)
	hbox.add_child(right)
	return hbox

static func add_readout(label: Label, readout: Variant) -> void:
	label.set_text(label.text + str(readout))

static func normalize_decimals(num: float, zeros: int, decimals: int, account_for_negative: bool = true) -> String:
	var num_snapped := snappedf(num,pow(.1,decimals))
	return str(num_snapped).pad_decimals(decimals).pad_zeros(zeros + ( int(num_snapped >= 0.0) if account_for_negative else 0))

static func set_style(label: Label, style: StyleBox) -> void:
	label.set(&"theme_override_styles/normal",style)
