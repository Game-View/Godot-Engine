extends Node3D

var sections : Array[MPSection] = []
@export var items : Array[MP_Item_Info] = []
var sectionContainer: VBoxContainer

var TOC : Dictionary

var TOC_callable = Callable(self, "_get_TOC")

var signatureCallable = Callable(Node,"_get_url_from_server")

var itemNum : int = 0

@onready var http_request = $Control/HTTPRequest
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	signatureCallable = $Control/HBoxContainer._get_url_from_server
	sectionContainer = $Control/HBoxContainer/SubViewportContainer/ScrollContainer/VBoxContainer
	$Control/HBoxContainer.sign_in("mikeytest","G4m3Vi3w!",TOC_callable.bind("game-view-marketplace-test","assets/toc/context.json"))
	#_get_TOC();
	#_fill_sections(items)
		

func _get_TOC(bucket: String, item_path: String, callback : Callable = Callable()):
	var http = HTTPRequest.new()
	add_child(http)
	http_request.connect("request_completed", _on_TOC_request_completed.bind(callback))
	http_request.request(signatureCallable.call(bucket,item_path))
	
func _on_TOC_request_completed(result, response_code, headers, body,callback: Callable = Callable()):
	print(response_code)
	print("X")
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var file_content = body.get_string_from_utf8()
		TOC = JSON.parse_string(file_content)
		_fill_items(TOC)
		if(callback.is_valid()):
			callback.call()
		http_request.disconnect("request_completed", _on_TOC_request_completed)
		
func _fill_items(TableOfContents : Dictionary):
	var curDetails;
	for itemName in TableOfContents:
		var curItem : MP_Item_Info = MP_Item_Info.new();
		curItem.title = itemName
		curDetails = TableOfContents[itemName]
		curItem.imagePath = curDetails['image']
		curItem.path = curDetails['path']
		curItem.USDprice = curDetails['price']
		items.append(curItem)
		var http_request_thread = HTTPRequest.new()
		add_child(http_request_thread)
		
		if not FileAccess.file_exists("user://"+curDetails['image'].substr(curDetails['image'].rfind("/")+1)):
			http_request_thread.connect("request_completed", _on_image_request_completed.bind(itemName,http_request_thread,curDetails['image']))
			var url = signatureCallable.call("game-view-marketplace-test",curDetails['image'])
			http_request_thread.request(url)
		else:
			curItem.imagePath = "user://"+curDetails['image'].substr(curDetails['image'].rfind("/")+1)
			_attach_img(itemName,curItem.imagePath)

func _add_to_sections(item: MP_Item_Info):
	var section : MPSection = load("res://scenes/MP_Selection.tscn").instantiate()
	item.imagePath = "user://"+item.imagePath.substr(item.imagePath.rfind("/")+1)
	section.assignDetails(item)
	section._attach_script(signatureCallable, item.path)
	sections.append(section)
	sectionContainer.add_child(section)
		
func _on_image_request_completed(result, response_code, headers, body,itemName,httpsthread,imgPath):
	print(imgPath.substr(imgPath.rfind("/")+1))
	print(itemName)
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		print("Download successful! File size: ", body.size(), " bytes")
		# Save the downloaded file to the user data directory.
		var file = FileAccess.open("user://" + imgPath.substr(imgPath.rfind("/")+1), FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			print("Image File saved to user:///" + imgPath.substr(imgPath.rfind("/")+1))
			_attach_img(itemName,"user://" + imgPath.substr(imgPath.rfind("/")+1))
			# You can now load the FBX file into your scene.
		else:
			print("Error saving file.")
	else:
		print("Image Download failed. Response code: ", response_code)

	itemNum+=1

func _attach_img(itemName, imgPath):
	for item : MP_Item_Info in items:
		if(item.title==itemName):
			_add_to_sections(item)
			return
