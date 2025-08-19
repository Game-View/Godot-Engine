class_name MPSection extends Control

@export var filePath : String
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func assignDetails(info : MP_Item_Info) -> bool:
	if(!(info.image && info.title && info.USDprice && info.path)):
		$VBoxContainer/MP_Section/Title.text = "Not Found"
		return false
	$VBoxContainer/MP_Section/Title.text = info.title
	$VBoxContainer/MP_Section/Price.text = "$" + str(info.USDprice)
	$VBoxContainer/MP_Section/Image.texture = info.image
	filePath = info.path
	return true
