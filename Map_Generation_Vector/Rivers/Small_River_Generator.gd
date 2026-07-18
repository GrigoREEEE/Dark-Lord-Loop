class_name Small_River_Generator
extends RefCounted

# Orthogonal directions only (no diagonals)
const DIRECTIONS: Array[Vector2] = [
	Vector2(0, -1), # UP
	Vector2(0, 1),  # DOWN
	Vector2(-1, 0), # LEFT
	Vector2(1, 0)   # RIGHT
]

## Generates a river from a starting point, updating the river mask along the way.
func generate_river(source: Vector2, terrain_data: Dictionary, mask_data: Dictionary) -> Array[Vector2]:
	var path: Array[Vector2] = []
	var current_pos: Vector2 = source
	
	# Extract masks for collision detection
	var ocean_mask: Dictionary = mask_data.get("ocean", {})
	var river_mask: Dictionary = mask_data.get("river", {})
	var lake_mask: Dictionary = mask_data.get("lake", {})
	var delta_mask: Dictionary = mask_data.get("delta", {})
	
	# Abort if the source is completely off the map
	if not terrain_data.has(current_pos):
		return path
		
	path.append(current_pos)
	river_mask[current_pos] = true # Mark the source as a river immediately
	
	while true:
		var current_height: float = terrain_data[current_pos]
		var lowest_neighbor: Vector2 = current_pos
		var lowest_height: float = current_height
		
		# 1. Look at all 4 adjacent cells to find the steepest downhill drop
		for dir in DIRECTIONS:
			var neighbor = current_pos + dir
			
			if terrain_data.has(neighbor):
				var neighbor_height: float = terrain_data[neighbor]
				
				# Must be strictly lower to flow
				if neighbor_height < lowest_height:
					lowest_height = neighbor_height
					lowest_neighbor = neighbor
					
		# 2. Check for local minima (pit)
		if lowest_neighbor == current_pos:
			# Water has nowhere lower to go. 
			# In a more advanced system, this is where you would spawn a lake!
			break
			
		# 3. Move the river to the lowest found neighbor
		current_pos = lowest_neighbor
		path.append(current_pos)
		
		# 4. Check if we hit an existing body of water
		var hit_water = (
			ocean_mask.has(current_pos) or 
			river_mask.has(current_pos) or 
			lake_mask.has(current_pos) or 
			delta_mask.has(current_pos)
		)
		
		# Mark the current cell as a river so future rivers can merge into it
		river_mask[current_pos] = true 
		
		if hit_water:
			break # Stop generating this river's path
			
	return path
