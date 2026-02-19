class_name Profiler

static var _timers = {}
static var _accumulators = {}

# Call this at the START of the function you want to measure
static func start(tag: String):
	_timers[tag] = Time.get_ticks_usec()

# Call this at the END of the function
# Prints: "[tag] took X ms"
static func end(tag: String):
	if not _timers.has(tag): return
	
	var start_time = _timers[tag]
	var duration_usec = Time.get_ticks_usec() - start_time
	var duration_ms = duration_usec / 1000000.0
	
	print("[%s] took %.2f s" % [tag, duration_ms])
	_timers.erase(tag)
