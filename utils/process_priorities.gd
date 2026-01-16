
class Process:
	enum Priorities {
		SINGLETONS = -1, # Ensures that singleton autoload nodes process first.
		REGULAR, # 0
		PERF_OVERLAY # Do perf overlay calcs last always
	}

class Physics:
	enum Priorities {
		SINGLETONS = -1, # Ensures that singleton autoload nodes process first.
		REGULAR, # 0, default for nodes
		BOUNDING_BOX, # 1
		SERIALIZER, # 2
		HIT_RESOLVER, # 3
		HISTORY_SAVER, # 4
		
		PERF_OVERLAY # Do perf overlay calcs last always
	}

static func set_singleton(node: Node) -> void:
	node.process_priority = Process.Priorities.SINGLETONS
	node.process_physics_priority = Physics.Priorities.SINGLETONS
