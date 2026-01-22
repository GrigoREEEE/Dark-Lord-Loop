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
