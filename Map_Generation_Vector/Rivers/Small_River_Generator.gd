class_name Small_River_Generator
extends RefCounted

signal termination(location_type: String, location: Vector2)

const DIRECTIONS: Array[Vector2] = [
	Vector2(0, -1), # UP
	Vector2(0, 1),  # DOWN
	Vector2(-1, 0), # LEFT
	Vector2(1, 0)   # RIGHT
]

# Generates a natural river flowing via steepest descent.
# Ends when it hits the Ocean, a Lake, a Delta, an existing River, or a local pit.
func generate_small_natural_river(
	width: int, 
	height: int, 
	ocean: Water_Pool, 
	terrain_data: Dictionary, 
	mask_data: Dictionary,
	river_data: Dictionary, # Mapping Vector2 -> Region for collision linking
	start_pos: Vector2
) -> River:
	
	var river = River.new()
	river.id = "RI" + str(randi() % 9999).pad_zeros(4)
	river.river_type = "Natural"
	river.source = start_pos
	
	# Extract masks for fast collision detection
	var ocean_mask: Dictionary = mask_data.get("ocean", {})
	var river_mask: Dictionary = mask_data.get("river", {})
	var lake_mask: Dictionary = mask_data.get("lake", {})
	var delta_mask: Dictionary = mask_data.get("delta", {})
	
	var current_pos: Vector2 = start_pos
	
	var step_count: int = 0
	var max_steps: int = width * height # Failsafe against infinite loops
	
	while step_count < max_steps:
		step_count += 1
		
		# --- 1. BOUNDARY CHECK ---
		if current_pos.x < 0 or current_pos.x >= width or current_pos.y < 0 or current_pos.y >= height:
			river.mouth = current_pos
			_add_unique_point(river.river_path, current_pos)
			termination.emit("out of bounds", current_pos)
			break
			
		# --- 2. COLLISION CHECKS ---
		# A. Hit the Ocean
		if ocean_mask.get(current_pos, false) == true:
			river.mouth = current_pos
			_add_unique_point(river.river_path, current_pos)
			ocean.rivers_in.append(river)
			termination.emit("ocean", current_pos)
			break
			
		# B. Hit an existing River
		if river_mask.get(current_pos, false) == true:
			river.mouth = current_pos
			_add_unique_point(river.river_path, current_pos)
			
			# Extract the specific Region we hit and register this river to it
			if river_data.has(current_pos):
				var hit_region: Region = river_data[current_pos]
				hit_region.rivers_in.append(river)
				
			termination.emit("river", current_pos)
			break
			
		# C. Hit a Lake
		if lake_mask.get(current_pos, false) == true:
			river.mouth = current_pos
			_add_unique_point(river.river_path, current_pos)
			termination.emit("lake", current_pos)
			break
			
		# D. Hit a Delta
		if delta_mask.get(current_pos, false) == true:
			river.mouth = current_pos
			_add_unique_point(river.river_path, current_pos)
			termination.emit("delta", current_pos)
			break
			
		# --- 3. RECORD PATH & MASK ---
		# If no collision, record the cell and mark it in the mask so future rivers can hit us.
		_add_unique_point(river.river_path, current_pos)
		river_mask[current_pos] = true
		
		# --- 4. FIND STEEPEST DESCENT ---
		var current_height: float = terrain_data.get(current_pos, 0.0) 
		var lowest_neighbor: Vector2 = current_pos
		var lowest_height: float = current_height
		
		for dir in DIRECTIONS:
			var neighbor = current_pos + dir
			
			if terrain_data.has(neighbor):
				var neighbor_height: float = terrain_data[neighbor]
				
				# Must be STRICTLY lower to flow
				if neighbor_height < lowest_height:
					lowest_height = neighbor_height
					lowest_neighbor = neighbor
					
		# --- 5. CHECK LOCAL MINIMUM ---
		if lowest_neighbor == current_pos:
			# Water has nowhere lower to go; stuck in a pit.
			river.mouth = current_pos
			termination.emit("local minima", current_pos)
			break
			
		# --- 6. MOVE ---
		current_pos = lowest_neighbor
		
	return river

func _add_unique_point(path: Array[Vector2], point: Vector2):
	if path.is_empty() or path.back() != point:
		path.append(point)

func clean_river_path(river: River, ocean_mask: Dictionary):
	var new_path: Array[Vector2] = []
	
	for i in range(river.river_path.size()):
		var pos = river.river_path[i]
		
		new_path.append(pos)
		
		if ocean_mask.get(pos, false) == true:
			river.mouth = pos
			break 
			
	river.river_path = new_path

func check_river_breach(river: River, beach_mask: Dictionary, mouth_segments_count: int) -> bool:
	if river.segments.is_empty():
		return false
		
	var start_of_mouth_index = max(0, river.segments.size() - mouth_segments_count)
	
	for i in range(start_of_mouth_index):
		var segment = river.segments[i]
		
		for cell in segment.points:
			if beach_mask.get(cell, false) == true:
				print("River Breach detected at segment ", i, " position ", cell)
				return true
				
	return false
