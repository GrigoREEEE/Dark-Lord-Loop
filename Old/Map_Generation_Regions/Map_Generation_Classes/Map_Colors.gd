extends Object

class_name Map_Colors

#################################################
############# GETTING COLORS ####################
#################################################

func get_pixel_color_dict(image):
	var pixel_color_dict = {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel_color = "#" + str(image.get_pixel(int(x), int(y)).to_html(false))
			if pixel_color not in pixel_color_dict:
				pixel_color_dict[pixel_color] = []
			pixel_color_dict[pixel_color].append(Vector2(x,y))
	return pixel_color_dict

#################################################
############# GENERATING COLORS #################
#################################################

func generate_colors(num : int):
	var returned_colors : Array[Color] = []
	for i in num:
		returned_colors.append(number_to_color(i))
	return returned_colors
	
# Generates a deterministic color from a number
func number_to_color(hs: int) -> Color:
	# Use a simple hash function to generate pseudo-random but deterministic values
	# Mix the bits using prime multipliers
	hs = (hs ^ 61) ^ (hs >> 16)
	hs = hs + (hs << 3)
	hs = hs ^ (hs >> 4)
	hs = hs * 0x27d4eb2d
	hs = hs ^ (hs >> 15)
	
	# Extract RGB components from the hash
	var r = (hs & 0xFF) / 255.0
	var g = ((hs >> 8) & 0xFF) / 255.0
	var b = ((hs >> 16) & 0xFF) / 255.0
	
	return Color(r, g, b)

#################################################
############# CORRECTING COLORS #################
#################################################

# Finds and corrects colors that are close to palette colors but not exact matches
# Returns a dictionary mapping incorrect colors to their corrected palette colors
static func get_color_corrections(palette: Array[Color], read_colors: Array[Color]) -> Dictionary:
	var corrections: Dictionary = {}
	
	# Create a set of palette colors for quick lookup
	var palette_set: Dictionary = {}
	for color in palette:
		palette_set[color] = true
	
	# Check each read color
	for read_color in read_colors:
		# Skip if color is already in palette (exact match)
		if palette_set.has(read_color):
			continue
		
		# Find the closest palette color
		var closest_color: Color = palette[0]
		var min_distance: float = INF
		
		for palette_color in palette:
			var distance = color_distance(read_color, palette_color)
			if distance < min_distance:
				min_distance = distance
				closest_color = palette_color
		
		# If we found a close match, add it to corrections
		# You can adjust this threshold based on your needs
		var threshold: float = 0.1  # Adjust sensitivity here
		if min_distance < threshold:
			corrections[read_color] = closest_color
	
	return corrections

# Calculate Euclidean distance between two colors in RGB space
static func color_distance(c1: Color, c2: Color) -> float:
	var dr = c1.r - c2.r
	var dg = c1.g - c2.g
	var db = c1.b - c2.b
	return sqrt(dr * dr + dg * dg + db * db)

# Alternative: Calculate distance with alpha channel
static func color_distance_with_alpha(c1: Color, c2: Color) -> float:
	var dr = c1.r - c2.r
	var dg = c1.g - c2.g
	var db = c1.b - c2.b
	var da = c1.a - c2.a
	return sqrt(dr * dr + dg * dg + db * db + da * da)

# Helper function: Apply corrections to an image
static func apply_corrections_to_image(image: Image, corrections: Dictionary) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel_color = image.get_pixel(x, y)
			if corrections.has(pixel_color):
				image.set_pixel(x, y, corrections[pixel_color])
				
static func example_usage():
	# Define your expected palette
	var palette: Array[Color] = [
		Color.RED,
		Color.GREEN,
		Color.BLUE,
		Color.WHITE,
		Color.BLACK
	]
	
	# Simulate colors read from an image (some slightly off)
	var read_colors: Array[Color] = [
		Color.RED,
		Color(1.0, 0.01, 0.01),  # Slightly off red
		Color.GREEN,
		Color(0.0, 0.98, 0.02),  # Slightly off green
		Color.BLUE,
		Color.WHITE
	]
	
	# Get corrections
	var corrections = get_color_corrections(palette, read_colors)
	
	print("Found %d color corrections:" % corrections.size())
	for incorrect_color in corrections:
		var correct_color = corrections[incorrect_color]
		print("  %s -> %s" % [incorrect_color, correct_color])
