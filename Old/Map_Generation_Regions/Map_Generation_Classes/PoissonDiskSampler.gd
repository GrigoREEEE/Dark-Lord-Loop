extends Object

class_name PoissonDiskSampler

static func generate_poisson_disk_samples(
	width: float, 
	height: float, 
	min_radius: float, 
	max_radius: float, 
	k: int = 30
) -> Array[Vector2]:
	# Use the smallest radius for cell size to ensure proper spacing
	var cell_size := min_radius / sqrt(2.0)
	
	# Determine grid dimensions
	var cols := int(ceil(width / cell_size))
	var rows := int(ceil(height / cell_size))
	
	# Initialize grid with -1 (no point)
	var grid := []
	grid.resize(rows)
	for i in range(rows):
		grid[i] = []
		grid[i].resize(cols)
		for j in range(cols):
			grid[i][j] = -1  # -1 means no point here
	
	var points: Array[Vector2] = []
	var active_list: Array[int] = []
	var radii: Array[float] = []  # Store each point's radius
	
	# First point is random with random radius
	var first_point := Vector2(randf_range(0, width), randf_range(0, height))
	var first_radius := randf_range(min_radius, max_radius)
	points.append(first_point)
	radii.append(first_radius)
	active_list.append(0)
	
	# Grid coordinates of first point
	var start_x := int(first_point.x / cell_size)
	var start_y := int(first_point.y / cell_size)
	grid[start_y][start_x] = 0  # stores index of point in points array
	
	while not active_list.is_empty():
		# Randomly select an active point
		var active_index := active_list[randi() % active_list.size()]
		var point := points[active_index]
		var point_radius := radii[active_index]
		var found := false
		
		# Try up to k times to find a valid new point
		for _i in range(k):
			# Generate random point in annulus around current point
			var angle := randf_range(0, 2 * PI)
			var new_radius := randf_range(min_radius, max_radius)
			var distance := randf_range(point_radius + new_radius, 2 * (point_radius + new_radius))
			var new_point := point + Vector2(cos(angle), sin(angle)) * distance
			
			# Check if point is within bounds
			if new_point.x < 0 or new_point.x >= width or new_point.y < 0 or new_point.y >= height:
				continue
			
			# Check neighboring cells for nearby points
			var grid_x := int(new_point.x / cell_size)
			var grid_y := int(new_point.y / cell_size)
			
			var valid := true
			
			# Check 5x5 grid around potential point
			for y in range(max(0, grid_y - 2), min(rows, grid_y + 3)):
				for x in range(max(0, grid_x - 2), min(cols, grid_x + 3)):
					var point_index = grid[y][x]
					if point_index != -1:
						var neighbor := points[point_index]
						var neighbor_radius := radii[point_index]
						var required_distance := new_radius + neighbor_radius
						if neighbor.distance_to(new_point) < required_distance:
							valid = false
							break
				if not valid:
					break
			
			if valid:
				# Add the new point
				points.append(new_point)
				radii.append(new_radius)
				active_list.append(points.size() - 1)
				grid[grid_y][grid_x] = points.size() - 1
				found = true
				break
		
		if not found:
			# Remove from active list if no valid points found after k attempts
			active_list.erase(active_index)
	
	return points
