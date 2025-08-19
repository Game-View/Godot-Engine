extends Node3D

@export var sections : Array[MPSection] = []
@export var items : Array[MP_Item_Info] = []
var sectionContainer: VBoxContainer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	sectionContainer = $Control/HBoxContainer/SubViewportContainer/ScrollContainer/VBoxContainer
	for section in sectionContainer.get_children():
		sections.append(section as MPSection)
	for i in range(0,items.size()):
		sections[i].assignDetails(items[i])
		


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
