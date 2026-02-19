extends Node
class_name River

var id: String = ""              # e.g. "RI0001"
var river_type: String = ""      # "Central", "Natural"
var source: Vector2 = Vector2.ZERO
var mouth: Vector2 = Vector2.ZERO
var river_path: Array[Vector2] = []
var segments: Array[Array] = []
var segment_flow: Array[float] = []
var river_mass: Array[Vector2] = []
var is_proper : bool = true

# New function to partition the river
func create_segments(chunk_size: int) -> void:
	# Clear any existing segments to prevent duplication
	segments.clear()
	
	if river_path.is_empty() or chunk_size <= 0:
		return

	var current_segment: Array[Vector2] = []
	
	for i in range(river_path.size()):
		var point = river_path[i]
		current_segment.append(point)
		
		# If this segment has reached the target size...
		if current_segment.size() >= chunk_size:
			segments.append(current_segment)
			
			# OPTIONAL: If you want visual continuity (lines connected),
			# you might want the next segment to start with this point.
			# For now, we do strict separation (ownership of tiles).
			current_segment = []
			
	# If there are leftovers (the end of the river), add them as the final segment
	if current_segment.size() > 0:
		segments.append(current_segment)

# Merges the last 'n' segments and then chops them into smaller chunks.
# Returns the number of NEW segments created (useful for updating 'mouth_segments' counts).
func resegment_delta(n_segments_from_end: int, target_chunk_size: int) -> int:
	if segments.size() < n_segments_from_end:
		return 0 # Not enough segments to process

	# 1. IDENTIFY & MERGE
	var start_index = segments.size() - n_segments_from_end
	var combined_cells: Array[Vector2] = []
	
	# Collect all cells from the target segments in order (Upstream -> Downstream)
	for i in range(start_index, segments.size()):
		combined_cells.append_array(segments[i])
	
	# 2. REMOVE OLD SEGMENTS
	# We pop from back 'n' times
	for k in range(n_segments_from_end):
		segments.pop_back()
		
	# 3. CHOP INTO NEW CHUNKS
	var current_idx = 0
	var total_cells = combined_cells.size()
	var new_segments_count = 0
	
	while current_idx < total_cells:
		# Determine the slice end
		var end_idx = min(current_idx + target_chunk_size, total_cells)
		
		# Extract the slice
		var new_chunk: Array[Vector2] = combined_cells.slice(current_idx, end_idx)
		
		# Add back to the main segments list
		segments.append(new_chunk)
		new_segments_count += 1
		
		current_idx += target_chunk_size
		
	return new_segments_count
		
	# print("Resegmented Delta: Merged ", n_segments_from_end, " into ", ceil(float(total_cells)/target_chunk_size), " chunks.")

# Removes river cells from the last segment if they overlap with the ocean mask.
# This fixes "spilling" where the river widening algorithm floods the ocean itself.
func clean_river_mouth(river: River, ocean_mask: Dictionary):
	if river.segments.is_empty():
		return

	# Get the last segment (the mouth of the river)
	var last_segment_index = river.segments.size() - 1
	var last_segment = river.segments[last_segment_index]
	
	var cleaned_segment: Array[Vector2] = []
	
	for cell in last_segment:
		# Check if this specific cell is Ocean
		# (If ocean_mask doesn't have the key, we assume False/Land for safety)
		var is_ocean = ocean_mask.get(cell, false)
		
		if not is_ocean:
			# Keep the cell if it is LAND
			cleaned_segment.append(cell)
			
	# Update the segment with only the valid land cells
	river.segments[last_segment_index] = cleaned_segment
	
# Combines the last 'n' segments of the river into a single "Delta Segment".
func merge_segments(n_segments_to_merge: int):
	if self.segments.size() < n_segments_to_merge + 1:
		return # River too short to make a delta
		
	var delta_cells: Array[Vector2] = []
	
	# 1. Collect all cells from the last N segments
	# We iterate backwards to pop them off easily
	for k in range(n_segments_to_merge):
		var segment = self.segments.pop_back()
		delta_cells.append_array(segment)
		
	# 2. Add the combined cluster back as a single segment
	# (We reverse the collection order if strictly needed, but for a set of cells it implies no order)
	self.segments.append(delta_cells)
	
	print("Delta created. River now has ", self.segments.size(), " segments.")
