extends Object

class_name DelaunayVoronoi

## Calculates Voronoi neighbors using Delaunay triangulation
## Points that share a Delaunay triangle edge are Voronoi neighbors

static func get_voronoi_neighbors(points: Array[Vector2]) -> Dictionary[Vector2, Array]:
	if points.size() < 2:
		return {}
	
	# Build neighbor dictionary from Delaunay triangulation
	var neighbors: Dictionary[Vector2, Array] = {}
	for p in points:
		neighbors[p] = []
	
	# Get Delaunay triangles
	var triangles = _delaunay_triangulation(points)
	
	# Extract edges from triangles - shared edges mean neighboring Voronoi cells
	for tri in triangles:
		_add_neighbor(neighbors, tri[0], tri[1])
		_add_neighbor(neighbors, tri[1], tri[2])
		_add_neighbor(neighbors, tri[2], tri[0])
	
	return neighbors


static func _add_neighbor(neighbors: Dictionary, p1: Vector2, p2: Vector2) -> void:
	if p2 not in neighbors[p1]:
		neighbors[p1].append(p2)
	if p1 not in neighbors[p2]:
		neighbors[p2].append(p1)


static func _delaunay_triangulation(points: Array[Vector2]) -> Array:
	var pts = points.duplicate()
	
	# Find bounding super-triangle
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	for p in pts:
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)
	
	var dx = max_x - min_x
	var dy = max_y - min_y
	var delta_max = max(dx, dy)
	var mid_x = (min_x + max_x) / 2.0
	var mid_y = (min_y + max_y) / 2.0
	
	# Create super-triangle vertices
	var p1 = Vector2(mid_x - 20 * delta_max, mid_y - delta_max)
	var p2 = Vector2(mid_x, mid_y + 20 * delta_max)
	var p3 = Vector2(mid_x + 20 * delta_max, mid_y - delta_max)
	
	# Initialize with super-triangle
	var triangles = [[p1, p2, p3]]
	
	# Incremental insertion
	for point in pts:
		var bad_triangles = []
		
		# Find triangles whose circumcircle contains the point
		for tri in triangles:
			if _in_circumcircle(point, tri):
				bad_triangles.append(tri)
		
		# Find boundary of polygonal hole
		var polygon = []
		for tri in bad_triangles:
			for i in range(3):
				var edge = [tri[i], tri[(i + 1) % 3]]
				var is_shared = false
				
				for other_tri in bad_triangles:
					if other_tri == tri:
						continue
					if _triangles_share_edge(tri, other_tri, edge):
						is_shared = true
						break
				
				if not is_shared:
					polygon.append(edge)
		
		# Remove bad triangles
		for tri in bad_triangles:
			triangles.erase(tri)
		
		# Re-triangulate the polygonal hole
		for edge in polygon:
			triangles.append([edge[0], edge[1], point])
	
	# Remove triangles containing super-triangle vertices
	var final_triangles = []
	for tri in triangles:
		if p1 not in tri and p2 not in tri and p3 not in tri:
			final_triangles.append(tri)
	
	return final_triangles


static func _in_circumcircle(point: Vector2, triangle: Array) -> bool:
	var a = triangle[0]
	var b = triangle[1]
	var c = triangle[2]
	
	var ab = a.x * a.x + a.y * a.y
	var cd = b.x * b.x + b.y * b.y
	var ef = c.x * c.x + c.y * c.y
	
	var circum_x = (ab * (c.y - b.y) + cd * (a.y - c.y) + ef * (b.y - a.y)) / (a.x * (c.y - b.y) + b.x * (a.y - c.y) + c.x * (b.y - a.y))
	var circum_y = (ab * (c.x - b.x) + cd * (a.x - c.x) + ef * (b.x - a.x)) / (a.y * (c.x - b.x) + b.y * (a.x - c.x) + c.y * (b.x - a.x))
	
	circum_x /= 2.0
	circum_y /= 2.0
	
	var circum = Vector2(circum_x, circum_y)
	var radius_sq = circum.distance_squared_to(a)
	var dist_sq = circum.distance_squared_to(point)
	
	return dist_sq <= radius_sq


static func _triangles_share_edge(tri1: Array, tri2: Array, edge: Array) -> bool:
	var count = 0
	for vertex in edge:
		if vertex in tri2:
			count += 1
	return count == 2
