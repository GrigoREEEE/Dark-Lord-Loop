class_name Climate_Generator
extends RefCounted

# --- Temperature Configurations (Celsius) ---
var north_winter: float = -8.0 
var north_summer: float = 14.0
var south_winter: float = 12.0
var south_summer: float = 32.0
var tropical_winter: float = 22.0
var tropical_summer: float = 30.0

var elevation_cooling_factor: float = 10.0

# --- Water Moderation Configurations ---
var maritime_moderation: float = 0.5 

# The base moderation strength of the river itself (0.5 means it acts exactly like the ocean)
var river_moderation: float = 0.5 
var river_radiation_radius: int = 3 
# How much moderation is lost per tile away? (0.33 means 0% effect at 3 tiles away)
var river_radiation_falloff: float = 0.33 

func generate_temperatures(terrain_data: Dictionary, mask_data: Dictionary, winter_tweak: float = 0.0, summer_tweak: float = 0.0) -> Dictionary:
	var temp_data: Dictionary = {}
	var ocean_mask: Dictionary = mask_data.get("ocean", {})
	var river_mask: Dictionary = mask_data.get("river", {}) 
	
	var min_y: float = INF
	var max_y: float = -INF
	
	for pos in terrain_data.keys():
		if pos.y < min_y: min_y = pos.y
		if pos.y > max_y: max_y = pos.y
			
	var range_y: float = max_y - min_y
	if range_y == 0: range_y = 1.0 

	# --- PASS 1: Base Temperatures ---
	for pos in terrain_data.keys():
		var height: float = terrain_data[pos]
		var is_ocean: bool = ocean_mask.get(pos, false)
		
		var lat_t: float = (pos.y - min_y) / range_y
		var winter_temp: float
		var summer_temp: float
		
		if lat_t < 0.85:
			var t: float = lat_t / 0.85
			var biased_t = pow(t, 0.65) 
			var smooth_t = smoothstep(0.0, 1.0, biased_t)
			
			winter_temp = lerp(north_winter, south_winter, smooth_t)
			summer_temp = lerp(north_summer, south_summer, smooth_t)
		else:
			var t: float = (lat_t - 0.85) / 0.15
			winter_temp = lerp(south_winter, tropical_winter, t)
			summer_temp = lerp(south_summer, tropical_summer, t)
		
		winter_temp += winter_tweak
		summer_temp += summer_tweak
		
		if height > 0.0:
			winter_temp -= height * elevation_cooling_factor
			summer_temp -= height * elevation_cooling_factor
			
		# Apply ocean moderation immediately
		if is_ocean:
			var yearly_average = (winter_temp + summer_temp) / 2.0
			winter_temp = lerp(winter_temp, yearly_average, maritime_moderation)
			summer_temp = lerp(summer_temp, yearly_average, maritime_moderation)
			
		temp_data[pos] = Vector2(winter_temp, summer_temp)

	# --- PASS 2: Radiate River Moderation ---
	var final_temp_data = temp_data.duplicate()
	
	for pos in terrain_data.keys():
		# Skip oceans (they are already moderated)
		if ocean_mask.get(pos, false):
			continue
			
		var is_river = river_mask.get(pos, false)
		var max_mod_strength = 0.0
		
		if is_river:
			max_mod_strength = river_moderation
		else:
			# Scan local neighborhood for rivers
			for dx in range(-river_radiation_radius, river_radiation_radius + 1):
				for dy in range(-river_radiation_radius, river_radiation_radius + 1):
					var neighbor_pos = pos + Vector2(dx, dy)
					
					if river_mask.get(neighbor_pos, false):
						var dist = pos.distance_to(neighbor_pos)
						if dist <= river_radiation_radius:
							# Calculate how much moderation reaches this tile
							var strength = river_moderation * clamp(1.0 - (dist * river_radiation_falloff), 0.0, 1.0)
							max_mod_strength = max(max_mod_strength, strength)
		
		# Pull the temperature towards the tile's yearly average based on moderation strength
		if max_mod_strength > 0.0:
			var winter = temp_data[pos].x
			var summer = temp_data[pos].y
			var yearly_average = (winter + summer) / 2.0
			
			final_temp_data[pos] = Vector2(
				lerp(winter, yearly_average, max_mod_strength),
				lerp(summer, yearly_average, max_mod_strength)
			)
			
	return final_temp_data
