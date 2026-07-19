class_name Small_River_Generator
extends RefCounted

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
			break
			
		# --- 2. COLLISION CHECKS ---
		# A. Hit the Ocean
		if ocean_mask.get(current_pos, false) == true:
			river.mouth = current_pos
			_add_unique_point(river.river_path, current_pos)
			ocean.rivers_in.append(river)
			break
			
		# B. Hit an existing River
		if river_mask.get(current_pos, false) == true:
			river.mouth = current_pos
			_add_unique_point(river.river_path, current_pos)
			
			# Extract the specific Region we hit and register this river to it
			if river_data.has(current_pos):
				var hit_region: Region = river_data[current_pos]
				hit_region.rivers_in.append(river)
			break
			
		# C. Hit a Lake or Delta
		if lake_mask.get(current_pos, false) == true or delta_mask.get(current_pos, false) == true:
			river.mouth = current_pos
			_add_unique_point(river.river_path, current_pos)
			break
			
		# --- 3. RECORD PATH & MASK ---
		# If no collision, record the cell and mark it in the mask so future rivers can hit us.
		_add_unique_point(river.river_path, current_pos)
		river_mask[current_pos] = true
		
		# --- 4. FIND STEEPEST DESCENT ---
		# Default fallback is 0.0 if somehow not in terrain_data
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
			break
			
		# --- 6. MOVE ---
		current_pos = lowest_neighbor
		
	return river

func _add_unique_point(path: Array[Vector2], point: Vector2):
	if path.is_empty() or path.back() != point:
		path.append(point)

# Trims the river path so it stops exactly where the NEW coastline begins.
func clean_river_path(river: River, ocean_mask: Dictionary):
	var new_path: Array[Vector2] = []
	
	for i in range(river.river_path.size()):
		var pos = river.river_path[i]
		
		# Always add the current point
		new_path.append(pos)
		
		# Check if this point is now Ocean (according to the post-erosion mask)
		if ocean_mask.get(pos, false) == true:
			# We hit the new water line!
			river.mouth = pos
			break # Stop adding points, discard the rest of the old path
	
	# Update the river object with the trimmed path
	river.river_path = new_path

# Checks if any "non-mouth" segment has accidentally grown into the beach.
# Returns TRUE if a breach is detected (bad state).
# Returns FALSE if the river is contained correctly.
func check_river_breach(river: River, beach_mask: Dictionary, mouth_segments_count: int) -> bool:
	if river.segments.is_empty():
		return false
		
	# Determine the boundary.
	# Any segment with an index LESS than this is considered "Inland" and must not touch the beach.
	var start_of_mouth_index = max(0, river.segments.size() - mouth_segments_count)
	
	# Iterate only through the inland segments
	for i in range(start_of_mouth_index):
		var segment = river.segments[i]
		
		for cell in segment.points: # Assuming segment is a Region object with a points array
			# If this cell is marked as beach in the mask
			if beach_mask.get(cell, false) == true:
				print("River Breach detected at segment ", i, " position ", cell)
				return true
				
	return false
