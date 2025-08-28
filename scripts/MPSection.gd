class_name MPSection extends Control
#This is a class of sections for the marketplace that provide a button, item details, image, and item file path
@export var filePath : String
var item_name : String
var img_path : String = ""
@onready var http_request = $HTTPRequest


var presigned_callback = Callable(Node,"_get_url_from_server")
		

#Adds load item as a button
func _attach_script(callback : Callable, download_url : String = "") -> void:
	presigned_callback = callback
	$VBoxContainer/MP_Section.pressed.connect(_load_item)

#Assigns all details about item, except the image
func assignDetails(info : MP_Item_Info) -> bool:
	if(!(info.title && info.USDprice && info.path)):
		$VBoxContainer/MP_Section/Title.text = "Not Found"
		return false
	$VBoxContainer/MP_Section/Title.text = info.title
	$VBoxContainer/MP_Section/Price.text = "$" + str(info.USDprice)
	filePath = info.path
	item_name = filePath.substr(filePath.rfind("/")+1)
	img_path = info.imagePath
	attachImage(img_path)
	return true

#Assigns image to item section
func attachImage(imgPath: String):
	var image = Image.load_from_file(imgPath)
	if image:
		var texture = ImageTexture.create_from_image(image)
		$VBoxContainer/MP_Section/Image.texture = texture
		print("Image attached successfully.")
	else:
		print("Failed to load texture at: ", imgPath)
		
#Loads the item into scene
func _spawn_item(loaded_model):
	if loaded_model:
		var final_model = _attach_extras(loaded_model)
		get_tree().root.add_child(final_model)
	else:
		print("Error: Failed to load the model.")
		return false

#Downloads item from server
func _download_item(path : String = filePath) -> void:
	MA_Import_Scene._request_file(filePath,presigned_callback,_first_time_create_scene)
	
#If the model hasn't been created, create it
func _first_time_create_scene(path):
	var model_instance;
	model_instance = await MA_Import_Scene.createScene(path, path.substr(path.rfind(".")+1))
	_spawn_item(model_instance)

#load item for creation
#1. See if it is in the user:// directory as a .tscn, or native server file
#2. If either is missing, download/convert it
#3. Spawn Item
func _load_item(path : String = filePath) -> void:
	var model_name = path.substr(path.rfind("/")+1, path.rfind(".")-path.rfind("/")-1)
	if(!path.begins_with("user")):
		path = "user://"+filePath.substr(filePath.rfind("/")+1)
	if not FileAccess.file_exists(path) and not ResourceLoader.exists("user://"+model_name+".tscn"):#1.
		print("Error: File not found, downloading now")
		_download_item(path)#2.
		return
	var model_instance;
	if !ResourceLoader.exists("user://"+model_name+".tscn"):
		print("user://"+model_name+".tscn")
		model_instance = await MA_Import_Scene.createScene(path, path.substr(path.rfind(".")+1))#2.
		ResourceSaver.save(model_instance,"user://"+model_name+".gltf")
		filePath = "user://"+model_name+".gltf"
	else:
		model_instance = ResourceLoader.load("user://"+model_name+".tscn").instantiate()
		print("Model Exists")
	_spawn_item(model_instance)#3.

#Attaches extra nodes like Rigidbody and Collision
func _attach_extras(item : Node3D) -> RigidbodyGizmo:
	var top_node = RigidbodyGizmo.new();
	var collider = CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	top_node.add_child(collider)
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
	top_node.name = item.name
	item.name = "base_Obj"
	return top_node
