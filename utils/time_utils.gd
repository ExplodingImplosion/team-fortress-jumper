const ByteUtils = Quack.ByteUtils
const Tickrate = Quack.Tickrate
const WindowUtils = Quack.WindowUtils
## Current time, in usec, at which [Quack] ran its [method Quack._process] function.
static var process_time_usec: int
## Previous time, in usec, at which [Quack] ran its [method Quack._process] function.
## At almost all times, this should match [member current_time], since it's only
## used for calculating [member delta_time] in [method Quack._process].
static var prev_process_time_usec: int
## The time, in usec, between the current frame's [member current_time] and the previous
## frame's [member current_time].
static var process_delta_time_usec: int
## Same as [member delta_time] but converted to seconds as a float.
static var process_delta_time_float: float
static var deferred_process_time_usec: int
static var idle_process_time_usec: int

## Current time, in usec, at which [Qauck] ran its [method Quack._physics_process] function.
static var physics_time_usec: int
## Previous time, in usec, at which [Quack] rant is [method Quack,_physics_process] function.
## At almost all times, this should match [member current_time_physics], since it's only
## used for calculating [member delta_time_physics] in [method Quack._physics_process].
static var prev_physics_time_usec: int
## The time, in usec, between the current physics frame's [member current_time_physics]
## and the previous physics frame's [member current_time_physics].
static var physics_delta_time_usec: int
## Used to calculate the proper time when [method Quack._physics_process] should be called.
## Updated once at [method Quack._init].
static var physics_start_time_usec: int
static var deferred_physics_time_usec: int
static var idle_physics_time_usec: int

## The cached version of the engine's current interpolation fraction. Same as
## [method get_interpfrac]. Updated every [method _process] frame.
static var interpfrac: float

## [Thread] that updates as often as possible, polling [Time.get_ticks_usec],
## applying it to [member current_time_thread], and calculating [member delta_time_thread]
## by subtracting [member last_time_thread] from [member current_time_thread],
## and then storing the current time as the last time by applying
## [member current_time_thread] to [member last_time_thread]
static var time_thread := Thread.new()

## Used to calculate [delta_time_thread] when [member time_thread] updates.
## [member time_thread] is currently disabled.
static var current_time_thread: int = 0
## The last time, in usec, at which [member time_thread] updated.
## [member time_thread] is currently disabled.
static var last_time_thread: float = 0
## Delta time, in usec, between [member current_time_thread] and the last time
## [member time_thread] was updated. [member time_thread] is currently disabled.
static var delta_time_thread: int = 0

const usec_in_seconds = ByteUtils.onemil
static func usec_get_usec_offset_from_second(usec: int) -> int:
	return usec%usec_in_seconds

const seconds_in_usec = ByteUtils.onemilfrac
static func usec_to_seconds(usec: int) -> float:
	return float(usec) * seconds_in_usec

static func seconds_to_usec(seconds: float) -> int:
	return int(seconds*usec_in_seconds)

static func seconds_to_usecf(sec: float) -> float:
	return sec*usec_in_seconds

const usec_in_msec = 1000
static func msec_to_usec(msec: int) -> int:
	return msec*usec_in_msec

static func msecf_to_usec(msecf: float) -> int:
	@warning_ignore("narrowing_conversion")
	return msecf*usec_in_msec

const seconds_in_msec = 1.0 / usec_in_msec
static func msec_to_seconds(msec: int) -> float:
	return float(msec)*seconds_in_msec

static func msecf_to_seconds(msec: float) -> float:
	return msec * seconds_in_msec

const msec_in_sec = 1000
static func seconds_to_msec(seconds: float) -> int:
	@warning_ignore("narrowing_conversion")
	return seconds * msec_in_sec

static func seconds_to_msecf(seconds: float) -> float:
	return seconds*msec_in_sec

static func usec_get_sec_offset_from_second(usec: int) -> float:
	return usec_to_seconds(usec_get_usec_offset_from_second(usec))

## Updates [member process_time_usec], [member prev_process_time_usec] calculates
## [member process_delta_time_usec] by subtracting the former two, and calculates
## [member process_delta_time_float] by converting [method process_delta_time_usec] to a [float] and
## multiplying it by [const seconds_in_usec]. Called every time
## [method Quack._process] is called.
static func update_process_times() -> void:
	process_time_usec = Time.get_ticks_usec()
	process_delta_time_usec = process_time_usec - prev_process_time_usec
	prev_process_time_usec = process_time_usec
	interpfrac = Engine.get_physics_interpolation_fraction()
	process_delta_time_float = usec_to_seconds(process_delta_time_usec)
	update_deferred_process_time.call_deferred()
	# Not called here, see udpate_deferred_process_time for details
	#update_idle_process_time.call_deferred.call_deferred()

static func update_deferred_process_time() -> void:
	deferred_process_time_usec = Time.get_ticks_usec()
	# NOTE: This is done here to move this to the back of the message queue
	# in case other call_deferreds were made. If another script function
	# "re-defers" itself and moves to the back of the queue (such as
	# perfoverlay funcs that capture these timings), this won't capture
	# it, but these should be rare enough to not be important.
	update_idle_process_time.call_deferred()

static func update_idle_process_time() -> void:
	idle_process_time_usec = Time.get_ticks_usec()

## Updates [member physics_time_usec], [member prev_physics_time_usec]
## and calculates [member physics_delta_time_usec] by subtracting the former two.
## Called every time [method Quack._physics_process] is called.
static func update_physics_times() -> void:
	physics_time_usec = Time.get_ticks_usec()
	physics_delta_time_usec = physics_time_usec - prev_physics_time_usec
	prev_physics_time_usec = physics_time_usec
	update_deferred_physics_time.call_deferred()
	# Not called here, see udpate_deferred_physics_time for details
	#update_idle_physics_time.call_deferred.call_deferred()

static func update_deferred_physics_time() -> void:
	deferred_physics_time_usec = Time.get_ticks_usec()
	# NOTE: This is done here to move this to the back of the message queue
	# in case other call_deferreds were made. If another script function
	# "re-defers" itself and moves to the back of the queue (such as
	# perfoverlay funcs that capture these timings), this won't capture
	# it, but these should be rare enough to not be important.
	update_idle_physics_time.call_deferred()

static func update_idle_physics_time() -> void:
	idle_physics_time_usec = Time.get_ticks_usec()

static func begin_physics_tracking() -> void:
	physics_start_time_usec = Time.get_ticks_usec()
	prev_physics_time_usec = physics_start_time_usec

static func start_time_thread() -> void:
	if time_thread.start(do_time_thread) != OK:
		print("fuck off")
		Quack.quit()

@warning_ignore("unused_parameter")
static func do_time_thread(n = null) -> void:
	for i in INF:
		current_time_thread = Time.get_ticks_usec()
		delta_time_thread = current_time_thread - prev_process_time_usec#_thread
#		print(delta_time_thread)
#		last_time_thread = current_time_thread
#		if current_time_thread != current_time:
#			print("thread: threaded time %s != %s"%[current_time_thread, current_time])

static func get_interpfrac() -> float:
	return Engine.get_physics_interpolation_fraction()

static func update_interpfrac() -> void:
	interpfrac = get_interpfrac()

## Returns [code]true[/code] if [member process_time_usec] is [code]0[/code]. Otherwise returns [code]false[/code].
static func is_startup() -> bool:
	return process_time_usec == 0

static func tick_time_value_towards(value: float, towards: float) -> float:
	value += process_delta_time_float
	return towards - value

static func tick_time_value_down(value: float) -> float:
	return value - process_delta_time_float

static func tick_time_value_up(value: float) -> float:
	return value + process_delta_time_float

static func frames_to_time(frames: int) -> float:
	return frames*Tickrate.physics_delta

static func frames_to_ms(frames: int) -> int:
	return seconds_to_msec(frames_to_time(frames))

static func frames_to_ms_f(frames: int) -> float:
	return seconds_to_msecf(frames_to_time(frames))

static func to_physics_frames(time: float) -> int:
	return int(time * Engine.physics_ticks_per_second)

static func frames_elapsed(since: int, time: int) -> bool:
	return Engine.get_physics_frames() >= since + time

static func get_time_left_in_frame_usec() -> int:
	var time: int = Time.get_ticks_usec()
	var target_time: int = WindowUtils.get_target_process_delta_usec()
	var next_time: int = process_time_usec + target_time
	return next_time - time

static func get_time_elapsed_in_frame_usec() -> int:
	return Time.get_ticks_usec() - process_time_usec

static func get_time_left_in_frame() -> float:
	return usec_to_seconds(get_time_left_in_frame_usec())

static func get_frame_frac() -> float:
	return float(get_time_elapsed_in_frame_usec()) / WindowUtils.get_target_process_delta_usec()

static func get_current_frame_pct() -> float:
	return get_frame_percentage(get_time_elapsed_in_frame_usec())

static func get_current_frame_pct_rem() -> float:
	return 100. - get_current_frame_pct()

static func get_frame_frac_remainder() -> float:
	return 1.0 - get_frame_frac()

static func is_physics_frame_interval(interval: int) -> bool:
	return Engine.get_physics_frames() % interval == 0

static func is_physics_time_interval(interval: float) -> bool:
	return is_physics_frame_interval(to_physics_frames(interval))

static func get_time_usec() -> float:
	return usec_to_seconds(Time.get_ticks_usec())

static func get_time_msec() -> float:
	return msec_to_seconds(Time.get_ticks_usec())

static func get_frame_percentage(time_usec: int) -> float:
	return 100.*(usec_to_seconds(time_usec)/WindowUtils.get_target_process_delta())

# Maybe move this to some type of performance namespace
static func get_func_time_usec(method: Callable) -> int:
	var t1: int
	var t2: int
	t1 = Time.get_ticks_usec()
	method.call()
	t2 = Time.get_ticks_usec()
	return t2-t1

static func get_func_frame_pct(method: Callable, print_func_frame_pct: bool = true) -> float:
	var time: float = get_frame_percentage(get_func_time_usec(method))
	if print_func_frame_pct:
		Console.write("Method %s took %s percent of a frame to complete."%[method.get_method(),time])
	return time

static func get_func_time_msec(method: Callable) -> int:
	return get_func_time_usec(method) / usec_in_msec

static func get_func_time_msecf(method: Callable) -> float:
	return float(get_func_time_usec(method)) / usec_in_msec

static func get_func_time_seconds(method: Callable) -> float:
	return usec_to_seconds(get_func_time_usec(method))

static func is_frame_out_of_time(max_frame_frac: float = .95) -> bool:
	return get_frame_frac() >= max_frame_frac or Engine.is_in_physics_frame()

static func check_func_time(function: Callable, include_stack := false) -> Variant:
	var t1: int
	var t2: int
	var to_return: Variant
	t1 = Time.get_ticks_usec()
	to_return = function.call()
	t2 = Time.get_ticks_usec()
	Console.write.call_deferred("Function %s %s took %sms"%[function.get_method(),str(function.get_bound_arguments()) if function.get_bound_arguments_count() > 0 else "",(float(t2-t1)/1_000_000.) * 1_000.])
	if include_stack:
		for dict:Dictionary in get_stack():
			Console.write_dict.call_deferred(dict)
	return to_return

static func get_time_since_physics_frame_usec() -> int:
	return Time.get_ticks_usec() - physics_time_usec
