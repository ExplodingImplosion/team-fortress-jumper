extends Window

const TimeUtils = Quack.TimeUtils
const BBCode = preload("res://utils/bbcode.gd")

const console_commands_script: GDScript = preload("res://utils/console/console_commands.gd")
const CONSOLE_SETTINGS_PATH = "quack/console/"
const CONSOLE_TRANSPARENCY_SETTING_PATH = CONSOLE_SETTINGS_PATH+"transparency"
const CONSOLE_TEXT_MAX_FRAME_DURATION_BEFORE_DEFERRMENT_SETTING_PATH = CONSOLE_SETTINGS_PATH+"text_max_frame_duration_before_deferrment"
const CONSOLE_SHORTCUTS_PATH = CONSOLE_SETTINGS_PATH+"shortcuts"
## Delimiter used to check for command aliases in [method parse_commands_script]
const alias_delimiter = "_aliases"
const err_color: Color = Color.RED
const warn_color: Color = Color.YELLOW
# so stupid that this needs to be a var instead of a const
var err_bbcode: String = err_color.to_html(false)
var warn_bbcode: String = warn_color.to_html(false)

var defer_readout_writes: bool = ProjectSettings.get_setting_safe(CONSOLE_SETTINGS_PATH+"defer_readout_writes",false) as bool

## Input action string to check for to toggle popping up the console.
const toggle := &"ui_console"
## Input action string to check for to toggle moving up through console
## history.
const up := &"ui_up"
## Input action string to check for to toggle moving down through console history.
const down := &"ui_down"
## Direction through [member history] array to go "up" (previous inputs) through history.
const UP := -1
## Direction through [member history] array to go "down" (more recent inputs) through history.
const DOWN := 1
## Minimum size of console window.
const MINSIZE := Vector2i(200,100)
## Default size, on startup, of console window.
const DEFAULTSIZE := Vector2i(600,488)
## Default position, on startup, of console window, relative to the top-right of
## the game's main window.
const DEFAULTPOS := Vector2i(40,40)
## Maximum number of commands that history can contain
const HISTORY_MAX_SIZE = 999
## Maximum offset/index in [member history]. Always equal to
## [member HISTORY_MAX_SIZE][code] - 1[/code].
const HISTORY_MAX_OFFSET = HISTORY_MAX_SIZE - 1
var readout := RichTextLabel.new()
var command_line := LineEdit.new()
var container := VBoxContainer.new()

## Number of commands that have been inputted. Used to check whether to overwrite
## old commands.
var hist_offset := 0
## Current position in history ([code]0[/code] = no commands have been inputted).
var current := 0
## Commands that have been previously inputted.
@warning_ignore("static_called_on_instance")
var history: PackedStringArray = setup_history()
## Whether or not a command has been inputted. Used in [method can_history_move].
var hist_empty: bool

var command_string_map: Dictionary[String,CommandInfo]
var commands: Array[CommandInfo]

var text_max_frame_duration_before_deferrment: float = ProjectSettings.get_setting_safe(CONSOLE_TEXT_MAX_FRAME_DURATION_BEFORE_DEFERRMENT_SETTING_PATH,0.1)

static func setup_history() -> PackedStringArray:
	var hist: PackedStringArray = []
	hist.resize(HISTORY_MAX_SIZE)
	return hist

const ProcessPriorities = Quack.ProcessPriorities
func _init():
	ProcessPriorities.set_singleton(self)
	setup_transparency()
	parse_commands()
	
	setup_window()
	setup_children()
	
	hide()
	var projectname: String = ProjectSettings.get_setting("application/config/name","Why da fuq do this project not have a name lol")
	write("Initializing %s..."%projectname)
	write(console_commands_script.helpstringhack())
	
	var cmdline_args := OS.get_cmdline_args()
	var cmdline_user_args := OS.get_cmdline_user_args()
	if !cmdline_args.is_empty():
		write("Scene opened: %s\n"%OS.get_cmdline_args()[1])
		cmdline_args = cmdline_args.slice(2)
	write_args("Command line args (does not include args consumed by the engine)",cmdline_args)
	write_args("User command line args",cmdline_user_args)
	# slice at 1 so the scene path 'argument' isn't passed.
	execute_args.bind(cmdline_args).call_deferred()
	execute_args.bind(cmdline_user_args).call_deferred()

## Literally just 3 spaces lol
const indent_string = "   " # 3 spaces

func write_if_error(error: Error, preceding_string: String = "") -> Error:
	if error != OK:
		push_err(preceding_string+error_string(error))
	return error

func write_args(arg_name: String, args: PackedStringArray) -> void:
	write(arg_name+":")
	for arg in args:
		write(indent_string+arg)
	writeln()

func execute_args(args: PackedStringArray) -> void:
	var i: int = 0
	while i < args.size():
		i = execute_cmdline_arg(i,args)

func write_arg_not_found(arg: String, idx: int) -> int:
	command_not_found(arg)
	increment_history(arg)
	# return the argument's index + 1 for iterating
	return idx+1

func execute_cmdline_arg(idx: int, cmdline_args: PackedStringArray) -> int:
	var command_string: String = cmdline_args[idx]
	var command_name: String
	var arg_separator_idx := command_string.findn("=")
	command_name = command_string if arg_separator_idx == -1 else command_string.substr(0,arg_separator_idx)
	var command_info: CommandInfo = command_string_map.get(command_name)
	# if the command line argument doesn't match a console command,
	if !command_info:
		return write_arg_not_found(command_string,idx)
	
	assert(command_string_map[cmdline_args[idx].split("=")[0]] == command_info,"argument %s which matches command %s != inputted command %s."%[cmdline_args[idx],command_string_map[cmdline_args[idx].split("=")[0]],command_info])
	
	var args: PackedStringArray = get_sub_commands(command_string.substr(arg_separator_idx+1),",")[0] if arg_separator_idx > -1 else ([] as PackedStringArray)
	@warning_ignore("static_called_on_instance")
	var arg_values := convert_args(args)
	command_info.add_default_args(arg_values)
	if not command_info.varadic:
		assert(arg_values.size() >= command_info.num_required_args and arg_values.size() <= command_info.num_args, "number of args %s doesn't match intended number of args for command (%s)."%[arg_values.size(),command_info.num_args])
		if arg_values.size() < command_info.num_required_args or arg_values.size() > command_info.num_args:
			write("Supplied num args %s != number of required args for command, %s required, %s max"%[arg_values.size(),command_info.num_required_args,command_info.num_args])
			return idx + 1 # + command_info.num_args
		execute_or_defer_launch_arg(command_info,arg_values)
	else:
		if arg_values.size() < command_info.num_required_args:
			write("Supplied num args %s < number of required args for command, %s"%[arg_values.size(),command_info.num_required_args])
			return idx + 1 # + command_info.num_args
		execute_or_defer_launch_arg(command_info,arg_values)
	
	increment_history(command_name + " " + " ".join(args))
	return idx + 1 # + command_info.num_args

func execute_or_defer_launch_arg(command_info: CommandInfo, args: Array[Variant]) -> void:
	if command_info.defer_launch_arg:
		execute_deferred_launch_arg(command_info.callable,args)
	else:
		Console.writeverb("Executing %s"%command_info.callable.get_method())
		command_info.callable.callv(args)

static func execute_deferred_launch_arg(command: Callable, args: Array) -> void:
	if TimeUtils.is_startup():
		Console.writeverb("Deferring %s"%command.get_method())
		Quack.defer_to_next_frame(execute_deferred_launch_arg.bind(command,args))
	else:
		Console.writeverb("Exeucting %s"%command.get_method())
		command.callv(args)

func set_background(box: StyleBox) -> void:
	set("theme_override_styles/embedded_border",box)

func set_opacity(opacity: float) -> void:
	transparent_bg = true
	var box := StyleBoxFlat.new()
	setup_stylebox(opacity,box)
	set_background(box)

func setup_stylebox(opacity: float, box: StyleBoxFlat) -> void:
	var color = RenderingServer.get_default_clear_color()
	color.a = opacity
	box.bg_color = color
	#box.border_color = color
	box.corner_detail = 5
	box.set_corner_radius_all(3)
	box.expand_margin_left = 8
	box.expand_margin_right = 8
	box.expand_margin_top = 32
	box.expand_margin_bottom = 6
	
	box.content_margin_left = 10
	box.content_margin_top = 28
	box.content_margin_right = 10
	box.content_margin_bottom = 8

func set_transparent() -> void:
	transparent_bg = true
	set_background(StyleBoxEmpty.new())

func setup_transparency() -> void:
	var transparency: float = ProjectSettings.get_setting_safe(CONSOLE_TRANSPARENCY_SETTING_PATH,0.0)
	if transparency == 0.0:
		return
		#set_background(StyleBoxFlat.new())
	elif transparency == 1.0:
		set_transparent()
	else:
		set_opacity(1.0-transparency)

func setup_window() -> void:
	set_title("Console")
	set_min_size(MINSIZE)
	set_position(DEFAULTPOS)
	setup_window_size.call_deferred()
	focus_entered.connect(Inputs.pause_gameplay_inputs)
	focus_exited.connect(Inputs.resume_gameplay_inputs)
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_requested.connect(disable)

func setup_children() -> void:
	setup_container()
	setup_label()
	setup_line()

func setup_window_size() -> void:
	Quack.setup_subwindow_size(self,DEFAULTSIZE)

func setup_container() -> void:
	add_child(container)
	@warning_ignore("static_called_on_instance")
	setup_margins(container)

@warning_ignore("shadowed_variable")
static func setup_margins(container: VBoxContainer) -> void:
	@warning_ignore("shadowed_variable")
	container.anchor_bottom = 1
	container.anchor_left = 0
	container.anchor_top = 0
	container.anchor_right = 1

func setup_label() -> void:
	@warning_ignore("static_called_on_instance")
	setup_label_properties(readout)
	container.add_child(readout)
	readout.set_focus_mode(Control.FOCUS_CLICK)

static func setup_label_properties(this_label: RichTextLabel) -> void:
	this_label.set_use_bbcode(true)
	this_label.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	this_label.set_scroll_follow(true)
	this_label.set_selection_enabled(true)
	this_label.set_context_menu_enabled(true)

func setup_line() -> void:
	@warning_ignore("static_called_on_instance")
	setup_line_properties(command_line)
	container.add_child(command_line)

func setup_line_properties(this_line: LineEdit) -> void:
	this_line.text_submitted.connect(execute_line)
	this_line.set_clear_button_enabled(true)
	this_line.set_keep_editing_on_text_submit(true)

func toggle_activation() -> void:
	@warning_ignore("standalone_ternary")
	disable() if is_visible() else activate()

func activate() -> void:
	popup()
	command_line.grab_focus()
#	if position.x > Quack.root.size.x or position.y > Quack.root.size.y:
	setup_window_size()
	# functionally the same as:
	#Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func disable() -> void:
	hide()
	command_line.clear()

func move_in_history(amount: int) -> void:
	current = int(clamp(current + amount, 0, history.size() - 1))
	command_line.set_text(history[current])
	command_line.caret_column = command_line.get_text().length()

func is_command_line_focused() -> bool:
	return gui_get_focus_owner() == command_line

func can_history_move() -> bool:
	return is_command_line_focused() and !hist_empty

func _process(_delta: float) -> void:
	parse_inputs()

func parse_inputs() -> void:
	if Input.is_action_just_pressed(toggle) or is_visible() and Input.is_action_just_pressed(&"ui_pause"):
		toggle_activation()
	if Input.is_action_just_pressed(up):
		if can_history_move():
			move_in_history(UP)
	if Input.is_action_just_pressed(down):
		if can_history_move():
			move_in_history(DOWN)
	if !is_visible():
		parse_shortcuts()

var shortcuts: Array[StringName] = ProjectSettings.get_setting_safe(CONSOLE_SHORTCUTS_PATH,[] as Array[StringName]) as Array[StringName]
func parse_shortcuts() -> void:
	# maybe make this mapped to a dictionary instead?
	for shortcut in shortcuts:
		if Input.is_action_just_pressed(shortcut):
			execute_line(shortcut)

func add_shortcut(shortcut: StringName) -> void:
	InputMap.add_action(shortcut)
	shortcuts.append(shortcut)
	ProjectSettings.set_setting(CONSOLE_SHORTCUTS_PATH,shortcuts)

func parse_commands() -> void:
	@warning_ignore("static_called_on_instance")
	parse_commands_script(console_commands_script, command_string_map, commands)
	# other scripts can go here

func reload_commands() -> void:
	command_string_map.clear()
	parse_commands()

## Writes a new line to the console and prints it to stdout.
func writeln() -> void:
	@warning_ignore("standalone_ternary")
	readout.append_text.call_deferred("\n") if defer_readout_writes else readout.append_text("\n")
	print("\n")

func writelns(amnt: int) -> void:
	for i in amnt:
		writeln()

func add_msg(s: String) -> void:
	@warning_ignore("standalone_ternary")
	readout.append_text.call_deferred(s+"\n") if defer_readout_writes else readout.append_text(s + "\n")

## Writes str([param v]) to the console and prints it to stdout, in its appropriate
## color according to its type.
func colored_writevar(v: Variant) -> void:
	var t := typeof(v)
	match t:
		TYPE_ARRAY:
			var string := "["
			for i in (v as Array):
				string += "\n%s"%BBCode.set_color_by_type(i)
			string += "\n]"
			write(string)
		TYPE_DICTIONARY:
			var string := "{"
			for i in (v as Dictionary):
				string += "\n%s	%s"%[
					BBCode.set_color_by_type(i),
					BBCode.set_color_by_type((v as Dictionary)[i])
				]
			string += "\n}"
			write(string)
		_:
			write(BBCode.set_color(str(v),BBCode.get_type_color(t)))

func colored_desc(desc: String, v: Variant) -> void:
	write("%s: %s"%[
		BBCode.set_color(desc,Color.YELLOW),BBCode.set_color_by_type(v)
	])

## Writes [param s] to the console and prints it to stdout,
## ONLY IF [method TimeUtils.is_physics_time_interval] [param i] is true.
func write_on_interval(interval: float, ...args) -> void:
	if TimeUtils.is_physics_time_interval(interval):
		write.callv(args)

## Writes all [param args] to the console and prints it to stdout.
func write(...args) -> void:
	var s: String = " ".join(args)
	add_msg(s)
	print_rich(s)

## Writes all [param args] to the console and prints it to stdout, separated by
## indents.
func twrite(...args) -> void:
	var s: String = "\t".join(args)
	add_msg(s)
	print_rich(s)

func cwrite(...args) -> void:
	var stringified: PackedStringArray = []
	stringified.resize(args.size())
	for i in stringified.size():
		stringified[i] = BBCode.set_color_by_type_nested(args[i],true)
	var s := " ".join(stringified)
	add_msg(s)
	print_rich(s)

# lmao
func cwrite_joined(join_string: String, ...args) -> void:
	var stringified: PackedStringArray = []
	stringified.resize(args.size())
	for i in stringified.size():
		stringified[i] = BBCode.set_color_by_type_nested(args[i],true)
	var s := join_string.join(stringified)
	add_msg(s)
	print_rich(s)

# lmao
func cwritenl(...args) -> void:
	var stringified: PackedStringArray = []
	stringified.resize(args.size())
	for i in stringified.size():
		stringified[i] = BBCode.set_color_by_type_nested(args[i],true)
	var s := "\n".join(stringified)
	add_msg(s)
	print_rich(s)

## Writes [param s] to the console and prints it to stdout IF
## the user argument --verbose is passed.
func writeverb(s: String) -> void:
	if OS.is_stdout_verbose():
		write(s)

## Writes [param s] to the console and prints it to stdout IF
## the user argument --verbose is passed.
func writerrverb(s: String) -> void:
	if OS.is_stdout_verbose():
		writerr(s)

## Writes [param s] to the console and prints it to stdout as
## an error.
func writerr(s: String) -> void:
	add_err_msg(s)
	printerr(s)

## Writes [param dict] to the console, and recursively writes any sub-dictionaries
## in the same format.
func write_dict(dict: Dictionary) -> void:
	var value: Variant
	for key in dict:
		value = dict[key]
		if value is Dictionary:
			write("%s:"%key)
			write_dict(dict)
		elif value is Array[Dictionary]:
			write("%s:"%key)
			for i in value:
				write_dict(i)
		else:
			write("%s: %s"%[key,value])

## Writes [param s] to the console in the [Color] [param color]
func write_in_color(s: String, color: Color) -> void:
	write(BBCode.set_color(s,color))

## Writes [param s] to the console and pushes an error in the editor
func push_err(s: String) -> void:
	add_err_msg(s)
	push_error(s)

## Writes [param s] to the console and pushes a warning in the editor
func push_warn(s: String) -> void:
	add_warn_msg(s)
	push_warning(s)

func add_err_msg(s: String) -> void:
	add_msg(BBCode.add_bbcode(s,err_bbcode))

func add_warn_msg(s: String) -> void:
	add_msg(BBCode.add_bbcode(s,warn_bbcode))

const ASSERTION_FAILED = "ASSERTION FAILED: %s"
## Only to be used in place of assertions. Prints [code]"ASSERTION FAILED: "[/code] +
## [param s] to the console without printing it to stdout, since assertions take
## care of that.
func get_assertfail_msg(assertion: bool, s: String, include_stack := false) -> void:
	if assertion:
		return
	if OS.is_debug_build():
		add_err_msg(ASSERTION_FAILED%s)
	else:
		push_err(ASSERTION_FAILED%s)
	# Maybe move this before pushing error
	if include_stack:
		for each in get_stack():
			add_err_msg(str(each))
	assert(assertion,s)

#func wrap_color(method: Callable, color: Color) -> void:
	#readout.push_color(color)
	#method.call()
	#readout.pusH_color(Color.WHITE)

## Executes the inputted command and its arguments, given as [param input]. The
## command is parsed as the first string delimited by a space, and 
func execute_line(input: String) -> void:
	if input.is_empty():
		return
	
	command_line.clear()
	write(str("> ", input))
	
	var sub_commands: Array[PackedStringArray] = get_sub_commands(input)
	
	for command in sub_commands:
		execute_command(command)

func execute_command(input_args: PackedStringArray) -> void:
	if input_args.is_empty():
		return
	
	var input := " ".join(input_args)
	
	var command_string: String = input_args[0]
	var command_info: CommandInfo = command_string_map.get(command_string)
	
	if command_info != null:
		if command_info.auth_only and (not Quack.is_3D_scene() or not (is_multiplayer_authority() or Quack.Network.peer == null)):
			return Console.writerr("%s is an authority-only command, and cannot be executed on a remote peer."%command_string)
		@warning_ignore("static_called_on_instance")
		var args := convert_args(input_args.slice(1))
		command_info.add_default_args(args)
		if command_info.varadic:
			command_info.callable.callv(args)
		else:
			var err: Error = args.resize(command_info.num_args) as Error
			assert(err == OK, "Ayo wtf got error %s"%error_string(err))
			command_info.callable.callv(args)
	else:
		command_not_found(command_string)
	
	increment_history(input)

func await_if_out_of_time() -> bool:
	await Quack.await_if_out_of_time(text_max_frame_duration_before_deferrment)
	return true

func get_text() -> String:
	return readout.get_parsed_text()

const dquote = "'"
const quote = '"'

static func get_occurrences(string: String, delim: String) -> PackedInt32Array:
	var array := PackedInt32Array()
	var occurrences: int = string.count(delim)
	if !occurrences:
		return array
	array.resize(occurrences)
	for i in occurrences:
		array[i] = string.find(delim,array[i-1])
	return array

static var semicolon_split := RegEx.create_from_string(';(?=(?:[^"]*"[^"]*")*[^"]*$)',true if OS.has_feature("editor") else false)
static var substring_split := RegEx.create_from_string('([^"]*)"|(\\S+)',true if OS.has_feature("editor") else false)

static func get_sub_commands(input: String, arg_separator_delim_char := " ") -> Array[PackedStringArray]:
	
	var cmds: Array[PackedStringArray]
	
	var i: int = 0
	var input_len := input.length()
	var in_smaller_string: bool = false
	var smaller_string_start_idx: int
	#var smaller_string_start_char: String
	var current_command: PackedStringArray = []
	var current_char: String
	var last_new_arg_idx: int
	while i < input_len:
		current_char = input[i]
		#Console.write(i,current_char)
		if current_char == ";":
			if not in_smaller_string:
				current_command.append(input.substr(last_new_arg_idx,i-last_new_arg_idx))
				cmds.append(current_command)
				#Console.write("colon not in smaller string, adding",current_command)
				current_command = []
				last_new_arg_idx = i + 1
		elif current_char == "\"":
			if in_smaller_string:
				in_smaller_string = false
				current_command.append(input.substr(smaller_string_start_idx,i-smaller_string_start_idx+1))
				last_new_arg_idx = i + 1
				#Console.write("Escaping smaller string and adding to command",current_command[-1])
			else:
				in_smaller_string = true
				smaller_string_start_idx = i
				#Console.write("Entering smaller string")
		elif current_char == arg_separator_delim_char:
			if not in_smaller_string:
				var arg := input.substr(last_new_arg_idx,i-last_new_arg_idx)
				if not arg.is_empty():
					current_command.append(arg)
				#Console.write("Aadding to command",current_command[-1])
				last_new_arg_idx = i+1
		i += 1
	if last_new_arg_idx < input_len:
		current_command.append(input.substr(last_new_arg_idx))
	if not current_command.is_empty():
		cmds.append(current_command)
	
	return cmds

func increment_history(input: String) -> void:
	history[hist_offset] = input
	hist_offset = wrapi(hist_offset+1,0,HISTORY_MAX_OFFSET)
	current = hist_offset

static func convert_args(args: PackedStringArray) -> Array[Variant]:
	var arg_values: Array[Variant] = []
	arg_values.resize(args.size())
	var value: Variant
	var arg: String
	for i in args.size():
		arg = args[i]
		value = str_to_var(arg)
		if value == null:
			# str_to_var is fucking stupid and doesnt pick up decimals without
			# a 0 in front of them, so this check fixes that shit
			if arg.is_valid_float():
				value = float(arg)
			else:
				value = args[i]
		arg_values[i] = value
	return arg_values

@warning_ignore("shadowed_variable")
func command_not_found(command_string: String) -> void:
	write(str("Command '", command_string, "' not found"))

var ping_start_time: int
@rpc("any_peer","unreliable") func receive_pingtest() -> void:
	update_ping_time.rpc_id(multiplayer.get_remote_sender_id())

@rpc("any_peer","unreliable") func update_ping_time() -> void:
	var time_received_at: int = Time.get_ticks_usec()
	var ping: int = time_received_at - ping_start_time
	Console.write("Peer %s pinged back after %s usec (%s seconds)."%[multiplayer.get_remote_sender_id(),ping,float(ping)*0.000001])

func profile(method: Callable, custom_text: String = "") -> Variant:
	var t1: int
	var t2: int
	var result: Variant
	t1 = Time.get_ticks_usec()
	result = method.call()
	t2 = Time.get_ticks_usec()
	t2 -= t1
	if custom_text.is_empty():
		custom_text = method.get_method()
	write(custom_text + " took %s useconds, %s seconds."%[t2,TimeUtils.usec_to_seconds(t2)])
	return result

static func get_method_names(script_methods: Array[Dictionary]) -> PackedStringArray:
	var method_names: PackedStringArray = []
	var script_methods_size: int = script_methods.size()
	
	method_names.resize(script_methods_size)
	
	for i in script_methods_size:
		method_names[i] = script_methods[i].name
	
	return method_names

# Do not look at the badness beyond this point, please

class CommandInfo:
	var callable: Callable
	var args: PackedByteArray
	const COMMAND_NAME_IDX = 0
	var aliases: PackedStringArray
	var num_args: int
	var num_default_args: int
	var num_required_args: int
	var varadic: bool = false
	var varadic_reason: String
	var args_info: Array[PackedStringArray]
	var help_string: String
	var defer_launch_arg: bool
	var auth_only: bool
	var default_args: Array[Variant]
	#var baked_args: Array[Variant]
	enum {ARG_NAME, ARG_TYPE_NAME}
	
	func _init(cmd: Callable, command_name: String) -> void:
		callable = cmd
		aliases.append(command_name)
	
	#func bake(args_to_bake: Array[Variant]) -> CommandInfo:
		#var new := CommandInfo.new(callable,"")
		#new.args = args
		#new.aliases = aliases
		#new.num_args = num_args
		#new.varadic = varadic
		#new.varadic_reason = varadic_reason
		#new.args_info = args_info
		#new.help_string = help_string
		#new.defer_launch_arg = defer_launch_arg
		#new.auth_only = auth_only
		#new.baked_args = args_to_bake
		#return new
	
	func get_command_name() -> String:
		return aliases[COMMAND_NAME_IDX]
	
	# the arg_types naming convention is hella stupid
	func add_args(arg_types: Array[Dictionary]) -> void:
		num_args = arg_types.size()
		args.resize(num_args)
		var arg_info: Dictionary
		for i in num_args:
			arg_info = arg_types[i]
			args[i] = arg_types[i].type as int
			args_info.append(CommandInfo.get_arg_info(arg_info))
	
	static func get_arg_info(arg_info: Dictionary) -> PackedStringArray:
		var info: PackedStringArray = []
		info.resize(2)
		info[ARG_NAME] = arg_info.name as String
		#var gaming1 = type_string(arg_info.type)
		#var gaming2 = arg_info.class_name
		#var gaming3 = arg_info.class_name.is_empty()
		#breakpoint
		info[ARG_TYPE_NAME] = type_string(arg_info.type) if arg_info.class_name.is_empty() else arg_info.class_name
		return info
	
	func add_shortened_aliases(string_map: Dictionary[String,CommandInfo]) -> void:
		var alias: String
		var shortened: String
		for i in aliases.size():
			alias = aliases[i]
			shortened = alias.replace("_","")
			if alias != shortened and !aliases.has(shortened):
				aliases.append(shortened)
				assert(!string_map.has(shortened),"Command String Map already has key %s."%[shortened])
				string_map[shortened] = self
	
	func get_aliases() -> PackedStringArray:
		return aliases.slice(1)
	
	func has_args() -> bool:
		return num_args > 0 or varadic
	
	func add_default_args(existing_args: Array[Variant]) -> void:
		existing_args.append_array(default_args.slice(existing_args.size()-num_required_args))

static func get_command_info(script: GDScript, script_method_name: String) -> CommandInfo:
	assert(script_method_name.ends_with(cmd_suffix),"Can't strip _cmd from script method %s if it doesn't end with _cmd."%script_method_name)
	return CommandInfo.new(Callable(script,script_method_name),script_method_name.trim_suffix(cmd_suffix))

const cmd_suffix = "_cmd"
const alias_suffix = "_aliases"
const help_suffix = "_help"
const debug_suffix = "_debug_only"
const defer_launch_arg_suffix = "_defer_launch_arg"
const auth_only_suffix = "_auth_only"
const varadic_reason_suffix = "_varadic_reason"
static func parse_commands_script(script: GDScript, string_map: Dictionary[String,CommandInfo], command_list: Array[CommandInfo]) -> void:
	var script_methods: Array[Dictionary] = script.get_script_method_list()
	var script_consts: Dictionary = script.get_script_constant_map()
	#var method_names: PackedStringArray = get_method_names(script_methods)
	
	var const_names := PackedStringArray(script_consts.keys())
	
	# Try adding every method as a command
	for method in script_methods:
		try_add_command(script,method as Dictionary[String,Variant],string_map)
	
	
	for constant_name:String in const_names:
		if constant_name.ends_with(defer_launch_arg_suffix):
			string_map[constant_name.trim_suffix(defer_launch_arg_suffix)].defer_launch_arg = true
		elif constant_name.ends_with(auth_only_suffix):
			string_map[constant_name.trim_suffix(auth_only_suffix)].auth_only = true
		# Remove debug-only methods if they're marked as debug-only
		# NOTE: This doesn't care what type of value constant_name matches.
		# Even if it's a string saying "actually I want this to work in
		# release builds, please don't make this debug only." If a constant
		# exists ending in _debug_only in a release build, then that command
		# won't be registered.
		elif !OS.is_debug_build() and constant_name.ends_with(debug_suffix):
			string_map.erase(constant_name.trim_suffix(debug_suffix))
	
	for command:CommandInfo in string_map.values():
		command_list.append(command)
	
	# Try adding every constant as a list of aliases for commands
	for constant_name:String in const_names:
		if constant_name.ends_with(alias_suffix):
			var constant_value: Variant = script_consts[constant_name]
			if constant_value is PackedStringArray:
				try_add_command_aliases(constant_name,constant_value,string_map)
			else:
				push_error("%s must be a PackedStringArray in order to be valid alias, but is %s."%[constant_name,type_string(typeof(constant_value))])
	
	# Create aliases that are just every existing command/alias, but without
	# underscores
	for info:CommandInfo in string_map.values():
		info.add_shortened_aliases(string_map)
	
	for constant_name in script_consts.keys():
		if constant_name.ends_with(help_suffix):
			var constant_value: Variant = script_consts[constant_name]
			if constant_value is String:
				try_add_command_help(constant_name,constant_value,string_map)
		elif constant_name.ends_with(varadic_reason_suffix):
			var constant_value: Variant = script_consts[constant_name]
			if constant_value is String:
				try_add_command_varadic_reason(constant_name,constant_value,string_map)

static func try_add_command(script: GDScript, method: Dictionary, string_map: Dictionary[String,CommandInfo]) -> void:
	if !(method.name as String).ends_with(cmd_suffix):
		return
	
	var command_info: CommandInfo = get_command_info(script,method.name as String)
	assert(!string_map.has(command_info.get_command_name()),"Tried to add a redundant command. string_map already has command %.s"%command_info.get_command_name())
	string_map[command_info.get_command_name()] = command_info
	command_info.add_args(method.args as Array[Dictionary])
	command_info.varadic = method.flags & MethodFlags.METHOD_FLAG_VARARG
	command_info.default_args = method.default_args as Array
	command_info.num_default_args = command_info.default_args.size()
	command_info.num_required_args = command_info.num_args - command_info.num_default_args

static func try_add_command_aliases(aliases_name: String, aliases: PackedStringArray, string_map: Dictionary[String,CommandInfo]) -> void:
	var command_name: String = aliases_name.trim_suffix(alias_suffix)
	if !string_map.has(command_name):
		@warning_ignore("standalone_ternary")
		push_warning("%s const was found, but no command %s exists."%[aliases_name,command_name]) if OS.is_debug_build() else null
		return
	
	var command_info: CommandInfo = string_map[command_name]
	command_info.aliases.append_array(aliases)
	for alias in aliases:
		string_map[alias] = command_info

static func try_add_command_help(help_name: String,help_string: String,string_map: Dictionary[String,CommandInfo]) -> void:
	var command_name: String = help_name.trim_suffix(help_suffix)
	if !string_map.has(command_name):
		return
	
	var command_info: CommandInfo = string_map[command_name]
	command_info.help_string = help_string

static func try_add_command_varadic_reason(varadic_reason_name: String, varadic_reason_string: String, string_map: Dictionary[String,CommandInfo]) -> void:
	var command_name := varadic_reason_name.trim_suffix(varadic_reason_suffix)
	if !string_map.has(command_name):
		return
	var command_info := string_map[command_name]
	command_info.varadic_reason = varadic_reason_string
