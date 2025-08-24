class_name MPSection extends Control

@export var filePath : String

@onready var http_request = $HTTPRequest

var TOC_JSON : Dictionary

var model_path : String
# Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#$VBoxContainer/MP_Section.pressed.connect(_request_file)

func _attach_script() -> void:
	$VBoxContainer/MP_Section.pressed.connect(_load_item)

func _request_file() -> void:
	var public_url = "https://gameview-marketplace.s3.us-east-2.amazonaws.com/"+filePath
	# Replace <region> with your bucket's actual AWS region.
	# Send the GET request to download the file.
	http_request.request(public_url)

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
	
func _on_request_completed(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		print("Download successful! File size: ", body.size(), " bytes")
		# Save the downloaded file to the user data directory.
		var file = FileAccess.open("res://" + model_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			print("File saved to res:///" + model_path)
			_load_item((file.get_path()));
			# You can now load the FBX file into your scene.
		else:
			print("Error saving file.")
	else:
		print("Download failed. Response code: ", response_code)
	
func _load_item(path : String = filePath) -> void:
	if not FileAccess.file_exists(path):
		print("Error: File not found at ", path)
		return
	
	# Load the resource from the user data path.
	var loaded_model = load(path)
	
	
	if loaded_model:
		# Check if the loaded resource is a valid 3D model scene.
		if loaded_model is ArrayMesh:
			var model_instance = MeshInstance3D.new()
			model_instance.mesh = loaded_model
			print("Mesh added to model and loaded to scene")
			var final_model = _attach_extras(model_instance)
			get_tree().root.add_child(final_model)
		if loaded_model is PackedScene:
			var model_instance = loaded_model.instantiate()
			var final_model = _attach_extras(model_instance)
			get_tree().root.add_child(final_model)
			print("Model loaded and added to scene.")
		else:
			print("Error: The loaded file is not a valid 3D scene.")
	else:
		print("Error: Failed to load the model.")

func _attach_extras(item : Node3D) -> RigidbodyGizmo:
	var top_node = RigidbodyGizmo.new();
	var collider = CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	top_node.add_child(collider)
	top_node.name = item.name
	item.name = "base_Obj"
	top_node.add_child(item)
	top_node.collider = collider
	if(item is MeshInstance3D):
		top_node.visual_node = item
		top_node.uniform_scale_update(item.scale)
	else:
		for child in item.get_children():
			if(child is MeshInstance3D):
				top_node.visual_node = child
				top_node.uniform_scale_update(child.scale)
				break
	top_node.set_collision_layer_value(1, false)
	top_node.set_collision_layer_value(3, true)
	top_node.set_collision_mask_value(3, true)
	top_node.set_collision_mask_value(2, true)
	MA_Gizmo.target_objects.append(top_node)
	return top_node
