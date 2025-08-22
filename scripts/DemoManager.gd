extends Node3D

@export var sections : Array[MPSection] = []
@export var items : Array[MP_Item_Info] = []
var sectionContainer: VBoxContainer

var itemNum : int = 0

@onready var http_request = $Control/HTTPRequest
var TOC : Dictionary
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	sectionContainer = $Control/HBoxContainer/SubViewportContainer/ScrollContainer/VBoxContainer
	$Control/HBoxContainer.sign_in("mikeytest","G4m3Vi3w!")
	#_get_TOC();
		

func _get_TOC() -> void:
	http_request.connect("request_completed", _on_TOC_request_completed)
	var TOC_url = "https://gameview-marketplace.s3.us-east-2.amazonaws.com/testTOC.txt?response-content-disposition=inline&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEJj%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMiJHMEUCIBHYMK5aMQC%2BZBFAeVCXbVt0GQ9LRAvod2DJw9RoBuq5AiEAxFNMN4AONnhtfJmWI35QjG%2BhZ9itYQnXswlePW1BTBkquQQI4f%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FARAAGgw2MjI5OTQ4OTY3NjYiDDh21kH8Uv6znOmHUiqNBMOwS1e%2FMAF7EZw4CZYJK92%2BazDsNfRebDFOO4gQagXGC%2FlDVN%2BOcCB7UsGLyEXLRSbrGOHHbg4VjHab4UC%2Bj%2BPZUie9xvrBzgjNIwWSQnOp4MrMGrXvYNgIbm2iTNKU%2FrZsL30L9KznyCemeqzNkXnXDoOlnauZyEHxf6drr4zbGu9wxx0Rn1%2BjBZO22BKU9fZfMYKlygQgF5UsuWJAHBkNygW%2B%2B2ur4OH7J%2BXBvTDxNL%2BLS1GNuALVGMOJTw7jrfxWPYhACfF%2F2J5MOOm3XUBrNDzBmaVxHLlTVwQY9W27b%2FQxwstmFaRgnThJzVF4mmcYA09cYsVYTulH5wbCFc5yJEOxxea24FMgwUAjRjGrhNP8x04oGdnuxg6%2B8kqrwdb2CkSyHwGjMneuO24Ntj6qLA4VvF0AB7bYd%2B7%2FkAxhGf8jIJUlcIZER1duS0XmCoCnwGftpQT%2BrGUilGUVwXH3LL7eycMis0fbMmpnQFzUU1nZn5NE5QWELgehzhwPsbzZkeaBhryA9sBF3qpxsuLJ8Fyxl84GD4J%2Fh4ejRYRJn9nUC5%2FFh%2FmtUM2wgfV3l%2BI7JA5XA2ZXVP9NWKBeQFTgUBhFs83YfR2TSv1J38wXhNBfjRf6FhIVL43wUOvs61RhEFXsWpBaVVLiD%2B0ETrv2c943wtycuz4M3tlRDgBYvrxiooTRNd1pRn0dDjCPspnFBjrFAp5BfcrJiujhBF%2B3rEByq1uZaspGPU%2Fb5zXhjB%2BY53UyNgJyppS9uBleh8Cw8TSuvvncW0XqEFrFzuF3S%2FJLi2kSFtYBtFuA81in4jnERAze66rLBf3Bqlmk8JpFR%2FRSz9aPFCg0qyoHOpAebIH2w2iTq81j5%2BbS3vS%2FDg8gxmf4CnkAZGN2fS2kzXPg2TZkU7xtj%2FE4JwGkc6BWVKYQztQ96b1Vv7LRMRGUVAmkkGq65J71au8rMna%2F5EPOElJnsoG%2FINpmaaJMpUBzEs%2BUT5C09h%2F%2BEjlc7ykChwVLS0qnShF1Ax0ZtJzeFkSnJYq2N9f00AhUSyhvpB5p6TmtfFO%2BUfqjfWpkR%2B4HnWJJoEjo3uhFbL%2FZJEP3Uw16hNwili%2BTn3zXnOX5qOY1rS4G2M6kzQfRXwMl8pkNeQ%2BagdoYFZfIPPM%3D&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=ASIAZCDLDW57IMCISPPF%2F20250821%2Fus-east-2%2Fs3%2Faws4_request&X-Amz-Date=20250821T000109Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host&X-Amz-Signature=0707d6530d9bde4a01ef89dd543f76ffe20f0f80a11ae1e08709496edfb004cc"
	#"https://gameview-marketplace.s3.us-east-2.amazonaws.com/testTOC.txt"
	http_request.request(TOC_url)
	
func _on_TOC_request_completed(result, response_code, headers, body):
	print(response_code)
	print("X")
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var file_content = body.get_string_from_utf8()
		TOC = JSON.parse_string(file_content)
		_fill_items(TOC)
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
		http_request_thread.connect("request_completed", _on_image_request_completed.bind(itemName,http_request_thread,curDetails['image']))
		var url = "https://gameview-marketplace.s3.us-east-2.amazonaws.com/"+curDetails['image']
		http_request_thread.request(url)

func _fill_sections(items : Array[MP_Item_Info]):
	for i in range(0,items.size()):
		var section : MPSection
		section.assignDetails(items[i])
		sections.append(section)
		sectionContainer.add_child(section)
		
func _on_image_request_completed(result, response_code, headers, body,itemName,httpsthread,imgPath):
	print(itemName)
	print("Y")
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		print("Download successful! File size: ", body.size(), " bytes")
		# Save the downloaded file to the user data directory.
		var file = FileAccess.open("res://" + imgPath, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			print("File saved to res:///" + imgPath)
			_attach_img(itemName,imgPath)
			# You can now load the FBX file into your scene.
		else:
			print("Error saving file.")
	else:
		print("Download failed. Response code: ", response_code)

	itemNum+=1
	if(itemNum==items.size()):
		_fill_sections(items)

func _attach_img(itemName, imgPath):
	for item : MP_Item_Info in items:
		if(item.title==itemName):
			var new_texture = load(imgPath)
			item.image = new_texture 
			#var image = Image.new()
			#var error = image.load(imgPath)
			#if error == OK:
				#var image_texture = ImageTexture.new()
				#image_texture.create_from_image(image)
				#item.image = new_texture 
			#else:
				#print("Failed to load image: ", error)
			return
			
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
