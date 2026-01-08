extends Object

class_name Voronoi_Generator

var map_colors : Map_Colors
var neighbour_seeker : DelaunayVoronoi
###################################
#####            V2           #####
###################################


func generate_voronoi_diagram(points : Array[Vector2], sprite : Sprite2D, img_size: Vector2i, type : String):
	map_colors = Map_Colors.new()
	neighbour_seeker = DelaunayVoronoi.new()
	randomize()
	var img : Image = Image.create(img_size.x, img_size.y, false, Image.FORMAT_RGB8)
	var colors : Array = []
	var num_cells : int = len(points)
	var color_possibilities : Array[Color] = map_colors.generate_colors(num_cells)
	
	
	print("instance, total number of points is " + str(num_cells))
	for i in points:
		var chosen_color : Color = color_possibilities[randi() % len(color_possibilities)]
		colors.append(chosen_color)
		color_possibilities.erase(chosen_color)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var dmin = float(img.get_size().length())
			var j = -1
			for i in range(num_cells):
				var d = (points[i] - Vector2(x, y)).length()
				if d < dmin:
					dmin = d
					j = i
			img.set_pixel(x, y, colors[j])

	var generated_texture = ImageTexture.create_from_image(img)
	if type == "biome":
		generated_texture = distort(150.0, 0.8, generated_texture)
	sprite.texture = generated_texture

func distort(strength : float, scaler : float, texture):
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = randi()
	
	var img = texture.get_image()
	var new_img = Image.create(img.get_width(), img.get_height(), false, img.get_format())
	
	for x in img.get_width():
		for y in img.get_height():
			# Get noise values
			var nx = noise.get_noise_2d(x * scaler, y * scaler) * strength
			var ny = noise.get_noise_2d(x * scaler + 1000, y * scaler + 1000) * strength
			
			# Sample original image with offset
			var src_x = clamp(x + nx, 0, img.get_width() - 1)
			var src_y = clamp(y + ny, 0, img.get_height() - 1)
			
			new_img.set_pixel(x, y, img.get_pixel(src_x, src_y))
	
	texture = ImageTexture.create_from_image(new_img)
	return texture
