static var threads: Dictionary[int,Variant] # Variant is always null, maybe turn this into CheckMode
const TimeUtils = Quack.TimeUtils
enum CheckMode {
	PROCESS=1,
	PHYSICS, # 2
	BOTH=PROCESS|PHYSICS, # 3
}

static var print_thread_checks := ProjectSettings.get_setting_safe("quack/debug/print_thread_checks",false) as bool
static func cleanup_threads() -> void:
	if threads.is_empty(): return
	for id in threads:
		if print_thread_checks:
			Console.writeverb("Checking thread %s..."%id)
		if WorkerThreadPool.is_task_completed(id):
			if print_thread_checks:
				Console.writeverb("Thread %s complete. Clearing."%id)
			var err := WorkerThreadPool.wait_for_task_completion(id)
			if err != OK:
				Console.push_err("Worker thread task ID %s got error %s even though marked as done."%[id,error_string(err)])
				assert(err != ERR_INVALID_PARAMETER, "fuck lol")
			if err != ERR_BUSY:
				threads.erase(id)

static func add_thread(callable: Callable, high_priority: bool = false, description := "") -> int:
	var id := WorkerThreadPool.add_task(callable,high_priority,description)
	threads[id] = null
	return id

# NOTE This is dependent on ThreadUtils being preloaded in QUack script
static func _static_init() -> void:
	setup_cleanup.call_deferred()

static func setup_cleanup() -> void:
	Quack.tree.process_frame.connect(cleanup_threads,CONNECT_DEFERRED)
	#Quack.tree.physics_frame.connect(cleanup_threads,CONNECT_DEFERRED)

static var locked_threads: Dictionary[Object,int]
static func add_locked_thread(object: Object, callable: Callable, high_priority := false, description := "") -> void:
	if locked_threads.has(object):
		var id := locked_threads[object]
		if id:
			var err := WorkerThreadPool.wait_for_task_completion(id)
			assert(err == OK,"Fuck! %s."%error_string(err))
	locked_threads[object] = WorkerThreadPool.add_task(callable,high_priority,description)

static func cleanup_locked_thread(object: Object, clear: bool = false) -> void:
	if locked_threads.has(object):
		var id := locked_threads[object]
		if id:
			var err := WorkerThreadPool.wait_for_task_completion(id)
			assert(err == OK,"Fuck! %s."%error_string(err))
		if clear:
			locked_threads.erase(object)
		else:
			locked_threads[object] = 0
