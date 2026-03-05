extends Water_Body
class_name River

var river_type: String = ""      # "Central", "Natural"
var source: Vector2 = Vector2.ZERO
var mouth: Vector2 = Vector2.ZERO
var river_path: Array[Vector2] = []
var segment_flow: Array[float] = []
var river_mass: Array[Vector2] = []
var is_proper : bool = true
var enters_into : Water_Body
var rivers_enter : Array[River] = []

# New function to partition the river into connected Region objects
func create_segments(chunk_size: int) -> void:
	# Clear any existing segments
	segments.clear()
	
	if river_path.is_empty() or chunk_size <= 0:
		return

	var current_points: Array[Vector2] = []
	var previous_region: Region = null
	
	for i in range(river_path.size()):
		current_points.append(river_path[i])
		
		# If this segment has reached the target size...
		if current_points.size() >= chunk_size:
			# Build the region and link it, then store it as the 'previous' for the next loop
			previous_region = _build_and_link_region(current_points, previous_region)
			
			# Reset points array for the next segment
			current_points = []
			
	# If there are leftovers (the end of the river), add them as the final Region
	if current_points.size() > 0:
		_build_and_link_region(current_points, previous_region)


# Helper function to instantiate, populate, and connect a River Region
func _build_and_link_region(points: Array[Vector2], prev_region: Region) -> Region:
	var new_region = Region.new()
	new_region.associated_water = self
	# Populate Region Properties
	# Using randi() for ID for now, but you could pass an incrementing counter if you prefer
	new_region.id = randi() 
	new_region.type = "Water"
	new_region.subtype = "River Segment"
	new_region.points = points.duplicate()
	new_region.size = points.size()
	
	# Establish the bi-directional connection
	if prev_region != null:
		new_region.regions_connect.append(prev_region)
		prev_region.regions_connect.append(new_region)
		
	# Add to the River's segment list
	segments.append(new_region)
	
	return new_region

# Merges the last 'n' regions and then chops them into smaller Region chunks.
# Returns the number of NEW regions created (useful for updating 'mouth_segments' counts).
func resegment_delta(n_segments_from_end: int, target_chunk_size: int) -> int:
	if segments.size() < n_segments_from_end:
		return 0 # Not enough segments to process

	# 1. IDENTIFY & MERGE
	var start_index = segments.size() - n_segments_from_end
	var combined_cells: Array[Vector2] = []
	
	# Collect all cells from the target regions' points array
	for i in range(start_index, segments.size()):
		combined_cells.append_array(segments[i].points)
	
	# Identify the last surviving region of the river (if there is one)
	# We need this to attach our newly chopped delta back to the main river.
	var previous_region: Region = null
	if start_index > 0:
		previous_region = segments[start_index - 1]
	
	# 2. REMOVE OLD REGIONS & CLEAN CONNECTIONS
	for k in range(n_segments_from_end):
		var popped_region = segments.pop_back()
		
		# Break the forward link from the surviving river to the deleted segments
		if previous_region != null and previous_region.regions_connect.has(popped_region):
			previous_region.regions_connect.erase(popped_region)
			
	# 3. CHOP INTO NEW CHUNKS
	var current_idx = 0
	var total_cells = combined_cells.size()
	var new_segments_count = 0
	
	while current_idx < total_cells:
		# Determine the slice end
		var end_idx = min(current_idx + target_chunk_size, total_cells)
		
		# Extract the slice
		var new_chunk: Array[Vector2] = combined_cells.slice(current_idx, end_idx)
		
		# Build the new Region and link it!
		# Passing 'previous_region' automatically hooks it up to the chain.
		previous_region = _build_and_link_region(new_chunk, previous_region)
		
		# Optional: Override the subtype so you know these are delta segments
		previous_region.subtype = "River Delta Segment"
		
		new_segments_count += 1
		current_idx += target_chunk_size
		
	return new_segments_count

# Removes river cells from the last Region if they overlap with the ocean mask.
# This fixes "spilling" where the river widening algorithm floods the ocean itself.
func clean_river_mouth(river: River, ocean_mask: Dictionary):
	if river.segments.is_empty():
		return

	# Get the last Region (the mouth of the river)
	var last_region: Region = river.segments.back()
	var cleaned_points: Array[Vector2] = []
	
	for cell in last_region.points:
		# Check if this specific cell is Ocean
		var is_ocean = ocean_mask.get(cell, false)
		
		if not is_ocean:
			# Keep the cell if it is LAND
			cleaned_points.append(cell)
			
	# Update the Region's data
	last_region.points = cleaned_points
	last_region.size = cleaned_points.size()
	
	# --- NEW SAFETY CLEANUP ---
	# If every single cell in this region was ocean, remove the region entirely
	# and clean up the linked list connections.
	if last_region.size == 0:
		var dead_region = river.segments.pop_back()
		
		if not river.segments.is_empty():
			var new_last_region = river.segments.back()
			new_last_region.regions_connect.erase(dead_region)
	
# Combines the last 'n' regions of the river into a single "Delta Region".
func merge_segments(n_segments_to_merge: int):
	# We require at least n + 1 segments so there is still a river left after making the delta!
	if self.segments.size() < n_segments_to_merge + 1:
		return 
		
	var delta_points: Array[Vector2] = []
	var popped_regions: Array[Region] = []
	
	# 1. Collect all points from the last N regions and remove them
	# We iterate backwards to pop them off easily
	for k in range(n_segments_to_merge):
		var popped_region = self.segments.pop_back()
		delta_points.append_array(popped_region.points)
		popped_regions.append(popped_region)
		
	# 2. Identify the surviving upstream region and clean up connections
	var previous_region: Region = null
	if not self.segments.is_empty():
		previous_region = self.segments.back()
		
		# Break the old forward connection to the deleted regions
		for popped in popped_regions:
			if previous_region.regions_connect.has(popped):
				previous_region.regions_connect.erase(popped)

	# 3. Create the new combined Delta Region
	var delta_region = Region.new()
	delta_region.associated_water = self
	delta_region.id = randi()
	delta_region.type = "Water"
	delta_region.subtype = "River Delta"
	delta_region.points = delta_points
	delta_region.size = delta_points.size()
	
	# 4. Link the new Delta to the surviving main river
	if previous_region != null:
		previous_region.regions_connect.append(delta_region)
		delta_region.regions_connect.append(previous_region)
		
	# 5. Add the combined cluster back as a single segment
	self.segments.append(delta_region)
	
	print("Delta Region created. River now has ", self.segments.size(), " segments.")
