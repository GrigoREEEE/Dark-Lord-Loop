extends Control

@export var sliders: Array[VSlider] = []
@export var sliders_to_value : Dictionary[VSlider, Label]
@export var locked_color: Color = Color(0.5, 0.5, 0.5, 0.3)  # Visual feedback for locked sliders
var locked_sliders: Dictionary = {}  # Tracks which sliders are locked
var slider_original_colors: Dictionary = {}  # Store original modulate colors

func _ready():
	# Connect all sliders to the same handler
	for slider in sliders:
		sliders_to_value[slider].text = str(slider.value)
		slider.value_changed.connect(_on_slider_changed.bind(slider))
		slider.gui_input.connect(_on_slider_gui_input.bind(slider))
		locked_sliders[slider] = false
		slider_original_colors[slider] = slider.modulate

func _on_slider_gui_input(event: InputEvent, slider: VSlider):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			toggle_lock(slider)

func toggle_lock(slider: VSlider):
	locked_sliders[slider] = !locked_sliders[slider]
	
	# Visual feedback
	if locked_sliders[slider]:
		slider.modulate = locked_color
		slider.editable = false
	else:
		slider.modulate = slider_original_colors[slider]
		slider.editable = true

func _on_slider_changed(new_value : int, changed_slider: VSlider):
	sliders_to_value[changed_slider].text = str(new_value)

#@export var slider_to_value: Dictionary[VSlider, Label]
#@export var locked_color: Color = Color(0.5, 0.5, 0.5, 0.3)  # Visual feedback for locked sliders
#
#var is_updating: bool = false
#var edited_slider : VSlider = null
#var locked_sliders: Dictionary = {}  # Tracks which sliders are locked
#var slider_original_colors: Dictionary = {}  # Store original modulate colors
#const TOTAL_POOL: float = 100.0
#var slider_hist : Dictionary[VSlider, float]
#
#func _process(delta: float) -> void:
	#for i in sliders:
		#slider_to_value[i].text = str(i.value)
#
#func _ready():
	## Connect all sliders to the same handler
	#for slider in sliders:
		#slider.drag_ended.connect(_on_slider_changed.bind(slider))
		#slider.gui_input.connect(_on_slider_gui_input.bind(slider))
		#locked_sliders[slider] = false
		#slider_original_colors[slider] = slider.modulate
	#
	## Initialize sliders to equal distribution
	#var equal_value = TOTAL_POOL / sliders.size()
	#for slider in sliders:
		#slider.min_value = 0
		#slider.max_value = 80
		#slider.value = equal_value
	#
	#for slider in sliders:
		#slider_hist[slider] = slider.value
#
#func _on_slider_gui_input(event: InputEvent, slider: VSlider):
	#if event is InputEventMouseButton:
		#if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			#toggle_lock(slider)
#
#func toggle_lock(slider: VSlider):
	#locked_sliders[slider] = !locked_sliders[slider]
	#
	## Visual feedback
	#if locked_sliders[slider]:
		#slider.modulate = locked_color
		#slider.editable = false
	#else:
		#slider.modulate = slider_original_colors[slider]
		#slider.editable = true
		#
#func update_slider(updated_slider : VSlider, amount_split : float):
	#print("updating slider" + updated_slider.name)
	#updated_slider.value = updated_slider.value - amount_split
	#slider_hist[updated_slider] = updated_slider.value
#
#func _on_slider_changed(is_changed : bool, changed_slider: VSlider):
	#var available_sliders : float = 0.0
	#var slider_to_edit : Array[VSlider] = []
	#var amount_split : float = 0.0
	#for i in sliders:
		#if i.editable == true and i != changed_slider:
			#available_sliders += 1.0
			#slider_to_edit.append(i)
	#
	#amount_split = (changed_slider.value - slider_hist[changed_slider])/available_sliders
	#print("amount to split is " + str(amount_split))
	#for i in slider_to_edit:
		#update_slider(i,amount_split)
	#
	#slider_hist[changed_slider] = changed_slider.value 
	#print(slider_hist)
	##if is_updating:
		#return
	#
	## Prevent locked sliders from being changed by user input
	#if locked_sliders[changed_slider]:
		#return
	#
	#is_updating = true
	#
	## Calculate how much the changed slider increased/decreased
	#var current_total = 0.0
	#var locked_total = 0.0
	#for slider in sliders:
		#current_total += slider.value
		#if locked_sliders[slider]:
			#locked_total += slider.value
	#
	## Calculate available pool for unlocked sliders
	#var available_pool = TOTAL_POOL - locked_total
	#
	## If the changed slider exceeds available pool, clamp it
	#if changed_slider.value > available_pool:
		#changed_slider.value = available_pool
		#is_updating = false
		#return
	#
	#var excess = current_total - TOTAL_POOL
	#
	#if abs(excess) > 0.0001:  # Small threshold to avoid floating point issues
		## Get all other sliders that are not locked
		#var other_sliders: Array[VSlider] = []
		#var other_total = 0.0
		#
		#for slider in sliders:
			#if slider != changed_slider and !locked_sliders[slider]:
				#other_sliders.append(slider)
				#other_total += slider.value
		#
		## If there are no unlocked sliders to take from, revert the change
		#if other_sliders.is_empty():
			#changed_slider.value = changed_slider.value - excess
			#is_updating = false
			#return
		#
		## Redistribute the excess proportionally from other unlocked sliders
		#if other_total > 0:
			#for slider in other_sliders:
				#var proportion = slider.value / other_total
				#var adjustment = excess * proportion
				#slider.value = max(0, slider.value - adjustment)
		#else:
			## If all other unlocked sliders are at 0, distribute evenly
			#var per_slider = excess / other_sliders.size()
			#for slider in other_sliders:
				#slider.value = max(0, -per_slider)
	#
	#is_updating = false
