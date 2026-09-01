extends Node

class_name River_Generator

# Generates a natural river flowing in ANY specified direction on a Hex Grid.
func generate_natural_river(
	world_data: World_Data,
	start_pos: Vector2,
	target_dir: Vector2,
	max_length: int = 1000000,
	meander_intensity: float = 1.0,
	start_progress: float = 0.0,
	stop_on_collision: bool = true,
	local_collision_mask: Dictionary = {},
	gravity_override: float = 0.7
):
		
	var width: int = world_data.grid_width
	var height: int = world_data.grid_height
	var ocean: Water_Pool = world_data.ocean
	var river_data: Dictionary = world_data.map_data["river"]
	var noise_seed: int = world_data.noise_seed
	var res_scale: float = world_data.res_scale
	var river = River.new()
	river.id = "RI" + str(randi() % 9999).pad_zeros(4)
	river.river_type = "Natural"
	
	# --- 1. CONFIGURATION ---
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.01 / res_scale 
	
	var gravity_strength: float = gravity_override
	var steer_strength: float = 0.5 
	var noise_cursor: float = 0.1

	# --- 2. INITIALIZATION ---
	river.source = start_pos
	var current_grid_pos: Vector2 = start_pos
	
	# Track an invisible physical cursor to accumulate fractional movement (drift)
	var current_physical: Vector2 = global._get_hex_physical_pos(start_pos)
	
	var current_dir: Vector2 = target_dir.normalized()
	river.river_path.append(river.source)
	
	var step_count: int = 0
	var max_steps: int = max(width, height) * 10 
	
	var fast_ocean_check: Dictionary[Vector2, bool] = {}
	for cell: Vector2 in ocean.all_cells:
		fast_ocean_check[cell] = true
	
	# --- 3. FLOW LOOP ---
	while step_count < max_steps:
		step_count += 1
		
		# --- A. CALCULATE DESIRED DIRECTION ---
		
		# Add the start_progress to the calculation so it skips the "straight" phase
		var progress: float = clamp(start_progress + (float(step_count) / 1000.0), 0.0, 1.0)
		var current_meander = lerp(0.1, meander_intensity, pow(progress, 2.0))
		
		var current_step_size: float = lerp(0.1, 1.2, progress) * current_meander
		
		noise_cursor += current_step_size
		var noise_val = noise.get_noise_2d(noise_cursor, 0.0)
		
		# 2. ANGLE: Higher intensity allows for sharper, wider turns
		# (Clamped to PI so it doesn't accidentally flow backwards in a perfect circle)
		var desired_angle = clamp(noise_val * PI * meander_intensity, -PI, PI)
		var steer_vector = target_dir.rotated(desired_angle)
		
		# 3. STEERING: Higher intensity overrides the target_dir "gravity" more effectively
		var dynamic_steer = clamp(steer_strength * meander_intensity, 0.0, 1.0)
		
		current_dir = current_dir.lerp(steer_vector, dynamic_steer)
		current_dir = current_dir.lerp(target_dir, gravity_strength).normalized()
		
		# --- B. MOVE PHYSICAL CURSOR & PICK CLOSEST HEX ---
		var hex_diameter = sqrt(3.0)
		current_physical += current_dir * hex_diameter

		var neighbors = global._get_hex_neighbors(current_grid_pos)
		var best_neighbor = current_grid_pos
		var best_dist = 999999.0

		for neighbor in neighbors:
			# If we are NOT stopping on collisions, forbid stepping on our own path.
			# If we ARE stopping on collisions, allow it so the collision check catches it!
			if not stop_on_collision and neighbor in river.river_path:
				continue 

			var neighbor_physical = global._get_hex_physical_pos(neighbor)
			var dist = current_physical.distance_to(neighbor_physical)

			if dist < best_dist:
				best_dist = dist
				best_neighbor = neighbor
				
		if best_neighbor == current_grid_pos:
			river.mouth = current_grid_pos
			break # Trapped!
			
		current_grid_pos = best_neighbor
		
		var chosen_physical = global._get_hex_physical_pos(current_grid_pos)
		current_physical = current_physical.lerp(chosen_physical, 0.5)
		
		# --- C. BOUNDS & RECORD ---

		# 1. Universal Out-of-Bounds Check
		if (current_grid_pos.x < 0 or current_grid_pos.x >= width or 
			current_grid_pos.y < 0 or current_grid_pos.y >= height):
			river.mouth = current_grid_pos
			current_grid_pos.x = clamp(current_grid_pos.x, 0, width-1)
			current_grid_pos.y = clamp(current_grid_pos.y, 0, height-1)
			_add_unique_point(river.river_path, current_grid_pos)
			break

		# 2. Check for Ocean Collision
		if fast_ocean_check.has(current_grid_pos):
			river.mouth = current_grid_pos
			_add_unique_point(river.river_path, current_grid_pos)
			ocean.rivers_in.append(river)
			break

		# 3. Check for Water Collisions (Other Rivers or Itself)
		# ADD 'and step_count > 2' to grant a small grace period at the spawn point!
		if stop_on_collision and step_count > 2:
			
			# Hit another river globally OR hit a local delta stream?
			if river_data.has(current_grid_pos) or local_collision_mask.has(current_grid_pos):
				river.mouth = current_grid_pos
				_add_unique_point(river.river_path, current_grid_pos)
				
				if river_data.has(current_grid_pos):
					var hit_region = river_data[current_grid_pos]
					if hit_region is Region: 
						hit_region.rivers_in.append(river)
				break
				
			# Hit its own path? (Self-intersection)
			elif current_grid_pos in river.river_path:
				river.mouth = current_grid_pos
				_add_unique_point(river.river_path, current_grid_pos)
				break

		_add_unique_point(river.river_path, current_grid_pos)
		
		# 4. Check Maximum Length Limit
		if max_length > 0 and river.river_path.size() > max_length:
			river.river_path.clear()
			river.is_proper = false
			return river
	print(len(river.river_path))
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

## Generates a natural river flowing in ANY specified direction.
## - start_pos: Pixel coordinate where the river begins.
## - target_dir: The general "Gravity" direction (e.g., Vector2.RIGHT for West->East).
## - max_length: Maximum allowed tile length. If exceeded, returns an empty/invalid river. (0 = no limit)
#func generate_natural_river(
	#world_data: World_Data,
	#start_pos: Vector2,
	#target_dir: Vector2,
	#max_length: int = 1000000
	#) -> River:
		#
	#var width: int = world_data.grid_width
	#var height: int = world_data.grid_height
	#var ocean: Water_Pool = world_data.ocean
	#var river_data: Dictionary = world_data.map_data["river"]
	#var noise_seed: int = world_data.noise_seed
	#var res_scale: float = world_data.res_scale
	#var river = River.new()
	#river.id = "RI" + str(randi() % 9999).pad_zeros(4)
	#river.river_type = "Natural"
	#
	## --- 1. CONFIGURATION ---
	#var noise = FastNoiseLite.new()
	#noise.seed = noise_seed
	#noise.frequency = 0.01 / res_scale 
	#
	#var gravity_strength: float = 0.2
	#var steer_strength: float = 0.5 
	#var noise_cursor: float = 0.0
#
	## --- 2. INITIALIZATION ---
	#river.source = start_pos
	#
	#var current_pos_float: Vector2 = start_pos
	## Initialize movement in the desired direction
	#var current_dir: Vector2 = target_dir.normalized()
	#
	#river.river_path.append(river.source)
	#
	#var step_count: int = 0
	## Allow more steps for diagonal paths
	#var max_steps: int = max(width, height) * 10 
	#
	## OPTIMIZATION: Convert the ocean's Array to a temporary Dictionary 
	## so we don't cause massive lag checking the array every single step.
	#var fast_ocean_check: Dictionary[Vector2, bool] = {}
	#for cell: Vector2 in ocean.all_cells:
		#fast_ocean_check[cell] = true
	#
	## --- 3. FLOW LOOP ---
	#while step_count < max_steps:
		#step_count += 1
		#
		## --- A. PROGRESSIVE MEANDERING ---
		## Create a progress factor from 0.0 to 1.0. 
		## (Adjust 400.0 to change how long it takes to reach maximum meandering)
		#var progress: float = clamp(float(step_count) / 1000.0, 0.0, 1.0)
		#
		## Dynamically change the noise step size!
		## Starts smooth and straight (0.1), ends chaotic and jagged (1.2)
		#var current_step_size: float = lerp(0.1, 1.2, progress)
		#
		## Safely advance the cursor
		#noise_cursor += current_step_size
		#
		## Get noise value (-1.0 to 1.0) using the cursor instead of step_count
		#var noise_val = noise.get_noise_2d(noise_cursor, 0.0)
		#
		## Calculate the noise steering vector relative to our target direction
		#var desired_angle = noise_val * PI # -180 to 180 degrees
		#var steer_vector = target_dir.rotated(desired_angle)
		#
		## Apply forces
		#current_dir = current_dir.lerp(steer_vector, steer_strength)
		#current_dir = current_dir.lerp(target_dir, gravity_strength)
		#
		## --- C. MOVE ---
		#current_pos_float += current_dir * 0.6 
		#
		## --- D. BOUNDS & RECORD ---
		#var current_grid_pos = current_pos_float.round()
		#
		## 1. Universal Out-of-Bounds Check
		#if (current_grid_pos.x < 0 or current_grid_pos.x >= width or 
			#current_grid_pos.y < 0 or current_grid_pos.y >= height):
			#
			#river.mouth = current_grid_pos
			## Clamp just for the final point so it doesn't crash map access
			#current_grid_pos.x = clamp(current_grid_pos.x, 0, width-1)
			#current_grid_pos.y = clamp(current_grid_pos.y, 0, height-1)
			#_add_unique_point(river.river_path, current_grid_pos)
			#break
#
		## 2. Check for Ocean Collision
		#if fast_ocean_check.has(current_grid_pos):
			#river.mouth = current_grid_pos
			#_add_unique_point(river.river_path, current_grid_pos)
			#
			## Register this river with the Ocean
			#ocean.rivers_in.append(river)
			#break
			#
		## 3. Check for Collision with Another River
		#if river_data.has(current_grid_pos):
			#river.mouth = current_grid_pos
			#_add_unique_point(river.river_path, current_grid_pos)
			#
			## Extract the specific Region we hit and register this river to it
			#var hit_region: Region = river_data[current_grid_pos]
			#hit_region.rivers_in.append(river)
			#break
			#
		#_add_unique_point(river.river_path, current_grid_pos)
		#
		## 4. Check Maximum Length Limit
		#if max_length > 0 and river.river_path.size() > max_length:
			#river.river_path.clear()
			#river.is_proper = false
			#return river
		#
	## Post-processing helper (assumed to exist)
	##_orthagonalize_river_path(river, noise_seed)
	#_bridge_hex_gaps(river)
	#return river
#
#func _add_unique_point(path: Array[Vector2], point: Vector2):
	#if path.is_empty() or path.back() != point:
		#path.append(point)
#
#
### Post-processing helper: Removes diagonal connections by inserting bridge cells
#func _orthagonalize_river_path(river: River, noise_seed : int) -> void:
	#var _rng = RandomNumberGenerator.new()
	#_rng.seed = noise_seed
	#
	#var old_path: Array[Vector2] = river.river_path
	#if old_path.is_empty():
		#return
#
	#var new_path: Array[Vector2] = []
	#
	## Always keep the starting point
	#new_path.append(old_path[0])
	#
	#for i in range(old_path.size() - 1):
		#var current: Vector2 = old_path[i]
		#var next: Vector2 = old_path[i+1]
		#
		## Check if the move is diagonal
		## (True if both X and Y change between steps)
		#if current.x != next.x and current.y != next.y:
			#
			## We need a "bridge" cell.
			## Option A: Move X first (Horizontal corner) -> Vector2(next.x, current.y)
			## Option B: Move Y first (Vertical corner)   -> Vector2(current.x, next.y)
			#
			#var bridge: Vector2
			#
			## Randomly pick one to prevent visual bias (zig-zag patterns)
			#if _rng.randf() > 0.5:
				#bridge = Vector2(next.x, current.y)
			#else:
				#bridge = Vector2(current.x, next.y)
				#
			#new_path.append(bridge)
		#
		## Always add the target cell after the potential bridge
		#new_path.append(next)
		#
	## Apply the new smoothed path back to the river object
	#river.river_path = new_path
#
## Trims the river path so it stops exactly where the NEW coastline begins.
#func clean_river_path(river: River, ocean_mask: Dictionary):
	#var new_path: Array[Vector2] = []
	#
	#for i in range(river.river_path.size()):
		#var pos = river.river_path[i]
		#
		## Always add the current point
		#new_path.append(pos)
		#
		## Check if this point is now Ocean (according to the post-erosion mask)
		#if ocean_mask.get(pos, false) == true:
			## We hit the new water line!
			#river.mouth = pos
			#break # Stop adding points, discard the rest of the old path
	#
	## Update the river object with the trimmed path
	#river.river_path = new_path
#
## Checks if any "non-mouth" segment has accidentally grown into the beach.
## Returns TRUE if a breach is detected (bad state).
## Returns FALSE if the river is contained correctly.
#func check_river_breach(river: River, beach_mask: Dictionary, mouth_segments_count: int) -> bool:
	#if river.segments.is_empty():
		#return false
		#
	## Determine the boundary.
	## Any segment with an index LESS than this is considered "Inland" and must not touch the beach.
	#var start_of_mouth_index = max(0, river.segments.size() - mouth_segments_count)
	#
	## Iterate only through the inland segments
	#for i in range(start_of_mouth_index):
		#var segment = river.segments[i]
		#
		#for cell in segment:
			## If this cell is marked as beach in the mask
			#if beach_mask.get(cell, false) == true:
				## We found a breach!
				## Optional: Print debug info to know where it happened
				#print("River Breach detected at segment ", i, " position ", cell)
				#return true
				#
	#return false
	#
#func _bridge_hex_gaps(river: River) -> void:
	#var old_path: Array[Vector2] = river.river_path
	#if old_path.size() <= 1:
		#return
#
	#var new_path: Array[Vector2] = []
	#
	## Always keep the starting point
	#new_path.append(old_path[0])
	#
	#for i in range(old_path.size() - 1):
		#var current: Vector2 = old_path[i]
		#var next: Vector2 = old_path[i+1]
		#
		## Prevent duplicate entries if the float rounding stayed on the same tile
		#if current == next:
			#continue
			#
		#var current_neighbors = global._get_hex_neighbors(current)
		#
		## If the next tile is a true hex neighbor, no gap exists!
		#if next in current_neighbors:
			#new_path.append(next)
		#else:
			## A gap exists! We jumped diagonally across a non-touching hex.
			## We must find a tile that touches BOTH 'current' and 'next' to bridge them.
			#var next_neighbors = global._get_hex_neighbors(next)
			#var bridge_found = false
			#
			#for neighbor in current_neighbors:
				#if neighbor in next_neighbors:
					#new_path.append(neighbor) # Insert the missing bridge cell
					#bridge_found = true
					#break # We only need one bridge to connect them
			#
			## Finally, add the target cell
			#new_path.append(next)
			#
	## Apply the unbroken, fully connected path back to the river object
	#river.river_path = new_path
#
## Helper function to find the 6 true touching neighbors in an offset hex grid
#func global._get_hex_neighbors(grid_pos: Vector2) -> Array[Vector2]:
	#var neighbors: Array[Vector2] = []
	#var is_odd_row: bool = int(grid_pos.y) % 2 != 0
	#
	## East and West are always the same on both rows
	#neighbors.append(grid_pos + Vector2(1, 0))  # Right
	#neighbors.append(grid_pos + Vector2(-1, 0)) # Left
	#
	#if is_odd_row:
		## Odd rows are shifted Right (+0.5 X)
		#neighbors.append(grid_pos + Vector2(0, -1))  # Top Left
		#neighbors.append(grid_pos + Vector2(1, -1))  # Top Right
		#neighbors.append(grid_pos + Vector2(0, 1))   # Bottom Left
		#neighbors.append(grid_pos + Vector2(1, 1))   # Bottom Right
	#else:
		## Even rows are normal
		#neighbors.append(grid_pos + Vector2(-1, -1)) # Top Left
		#neighbors.append(grid_pos + Vector2(0, -1))  # Top Right
		#neighbors.append(grid_pos + Vector2(-1, 1))  # Bottom Left
		#neighbors.append(grid_pos + Vector2(0, 1))   # Bottom Right
		#
	#return neighbors
