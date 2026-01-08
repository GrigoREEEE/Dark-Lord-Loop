extends Node2D

@export var area1_label : Label
@export var area2_label : Label

var first_army : int = 0
var second_army : int = 0

func _ready():
	pass

func _process(delta):
	first_army += 1
	second_army += 2
	area1_label.text = "Troops: " + str(first_army)
	area2_label.text = "Troops: " + str(second_army)
