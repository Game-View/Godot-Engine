class_name MA_Import_Scene extends Node

static var instance : MA_Import_Scene

func _ready() -> void:
	if(!instance):
		instance = self

#Sort through file type
static func createScene(model_path: String, file_type : String) -> Node:
	match file_type:
		"fbx":
			return await create_node_with_fbx(model_path,model_path.substr(0,model_path.rfind(".")) + ".gltf")
		"obj": #obj still uses fbx2gltf_path
			return await create_node_with_fbx(model_path,model_path.substr(0,model_path.rfind(".")) + ".gltf")
		_:
			return null

#Converts FBX file to GLTF file depending on System type
static func convert_fbx_to_gltf(fbx_path: String, gltf_path: String) -> bool:
	# Check if the .fbx file exists
	if not FileAccess.file_exists(fbx_path):
		print("Error: .fbx file does not exist at: ", fbx_path)
		return false
	
	# Path to the FBX2glTF binary (bundled with the game)
	var fbx2gltf_path = ""
	if OS.get_name() == "Windows":
		fbx2gltf_path = "res://tools/FBX2glTF-windows-x86_64/FBX2glTF-windows-x86_64.exe"
	elif OS.get_name() in ["Linux", "X11"]:
		fbx2gltf_path = "res://tools/FBX2glTF-linux-x86_64/FBX2glTF-linux-x86_64"
	elif OS.get_name() == "macOS":
		fbx2gltf_path = "res://tools/FBX2glTF-macos-x86_64/FBX2glTF-macos-x86_64"
	else:
		print("Error: Unsupported platform for FBX2glTF.")
		return false
	
	# Check if FBX2glTF exists
	if not FileAccess.file_exists(fbx2gltf_path):
		print("Error: FBX2glTF binary not found at: ", fbx2gltf_path)
		return false
	
	# Execute FBX2glTF to convert .fbx to .gltf
	var output = []
	#Arguments
	var args = ["--input", ProjectSettings.globalize_path(fbx_path), "--output", ProjectSettings.globalize_path(gltf_path)]
	var exit_code = OS.execute(ProjectSettings.globalize_path(fbx2gltf_path), args, output, true)
	if exit_code != 0:
		print(args)
		print("Error: FBX2glTF conversion failed. Exit code: ", exit_code, " Output: ", output)
		return false
	
	# Verify the .gltf file was created
	if not FileAccess.file_exists(gltf_path):
		print("Error: .gltf file was not created at: ", gltf_path)
		return false
	
	print("Successfully converted .fbx to .gltf at: ", gltf_path)
	return true
	
# Converts FBX to GLTF, then makes the GLTF available to the ResourceLoader
static func create_node_with_fbx(fbx_path: String, gltf_path: String) -> Node:
	if not FileAccess.file_exists(fbx_path):
		print("Error: .fbx file does not exist at: ", fbx_path)
		return null
	var converted = convert_fbx_to_gltf(fbx_path,gltf_path)
	if not FileAccess.file_exists(gltf_path):
		print("FBX to GLTF Conversion Failed: ",fbx_path)
		return null
	return await make_gltf_available(gltf_path)

#Makes the GLTF available to the ResourceLoader
static func make_gltf_available(save_path: String) -> Node:
	#If in editor mode
	if Engine.is_editor_hint():
		# Trigger import in the editor
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			var filesystem = editor_interface.get_resource_filesystem()
			filesystem.scan()  # Trigger filesystem scan to detect new file
			# Wait for scan to complete (asynchronous)
			await filesystem.filesystem_changed
			print("Filesystem scan completed")
			# Load the resource
			if ResourceLoader.exists(save_path):
				var resource = ResourceLoader.load(save_path)
				if resource is PackedScene:
					print("GLTF loaded as PackedScene: ", save_path)
					# Instance the scene
					return resource.instantiate()
				elif resource:
					print("GLTF loaded as resource: ", resource)
				else:
					print("Failed to load GLTF resource")
			else:
				print("GLTF resource not found at: ", save_path)
	#If in play mode
	else:
		return load_gltf_at_runtime(save_path)
	return null
		
#Loads the GLTF at runtime so ResourceLoader can see it
static func load_gltf_at_runtime(save_path: String) -> Node:
	# Read the GLTF file
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file:
		var body = file.get_buffer(file.get_length())
		file.close()
		# Parse GLTF
		var gltf_document = GLTFDocument.new()
		var gltf_state = GLTFState.new()
		var error = gltf_document.append_from_buffer(body, save_path, gltf_state)
		if error == OK:
			# Generate a Node (scene) from the GLTF
			var root_node = gltf_document.generate_scene(gltf_state)
			if root_node:
				print("GLTF loaded and instanced at runtime")
			else:
				print("Failed to generate scene from GLTF")
				return null
			#Save as a PackedScene for future use
			var scene = PackedScene.new()
			scene.pack(root_node)
			scene.resource_name = save_path.substr(save_path.rfind("/"),save_path.rfind("."))
			ResourceSaver.save(scene, save_path.substr(0,save_path.rfind("."))+".tscn")
			print("GLTF saved as PackedScene: ",save_path.substr(0,save_path.rfind("."))+".tscn")
			return root_node
		else:
			print("Failed to parse GLTF: ", error)
	else:
		print("Failed to read GLTF file: ", FileAccess.get_open_error())
	return null

#Downloads item file after _request_file is complete
static func download_item(result, response_code, headers, body, item_name, callback: Callable,httpRequest):
	print(response_code)
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		print("Download successful! File size: ", body.size(), " bytes")
		# Save the downloaded file to the user data directory.
		var file = FileAccess.open("user://"+item_name, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			callback.call("user://"+item_name)
		else:
			print("Error saving file.")
			
	if(httpRequest):
		httpRequest.queue_free()
		

#Request item file from server
static func _request_file(file_path: String, presign_callback : Callable,callback : Callable) -> void:
	var http = HTTPRequest.new()
	instance.add_child(http)
	print("Requesting file: " + file_path)
	http.connect("request_completed", download_item.bind(file_path.substr(file_path.rfind("/")+1),callback,http)) #next step
	http.request(presign_callback.call("game-view-marketplace-test",file_path))
