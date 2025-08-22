extends Node

const REGION = "us-east-1"   #Your region
const USER_POOL_ID = "us-east-1_1i60DZnE2"   #Your user pool ID
const CLIENT_ID = "3c9h80tqv3er2rgi388gl0cnt1"   #App client ID
const IDENTITY_POOL_ID = "us-east-1:eb5e7e93-8fd8-4f80-8434-85807e43992a"   #Identity pool ID
const CLIENT_SECRET = "pvj4igkvm1cmrslmfihqcr7jnkrj51j1oeosg3eh5h3rmrjf635"


var temp_access_key: String
var temp_secret_key: String
var temp_session_token: String

func generate_secret_hash(username: String, client_id: String, client_secret: String) -> String:
	# Concatenate username and client_id as a UTF-8 buffer
	var message_bytes = (username + client_id).to_utf8_buffer()
	
	# Convert client secret to UTF-8 buffer for key
	var key_bytes = client_secret.to_utf8_buffer()

	# Generate HMAC-SHA256
	var hmac_digest = Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key_bytes, message_bytes)
	
	# Base64-encode the result
	var base64_digest = Marshalls.raw_to_base64(hmac_digest)
	
	print(base64_digest)
	return base64_digest

func sign_in(username: String, password: String):
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_sign_in_completed)
	var secret_hash = generate_secret_hash(username, CLIENT_ID, CLIENT_SECRET)
	var endpoint = "https://cognito-idp." + REGION + ".amazonaws.com/"
	var headers = ["Content-Type: application/x-amz-json-1.1", "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth"]
	var body = JSON.stringify({
		  "AuthParameters": {"USERNAME": username, "PASSWORD": password, 
		  "SECRET_HASH": secret_hash},
		  "AuthFlow": "USER_PASSWORD_AUTH",
		  "ClientId": CLIENT_ID
	},"\t")
	http.request(endpoint, headers, HTTPClient.METHOD_POST, body)

func _on_sign_in_completed(result, response_code, headers, body):
	print(body)
	print(body.get_string_from_utf8())
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		var id_token = response["AuthenticationResult"]["IdToken"]
		get_identity_id(id_token)   #Next step
	else:
		print("Sign-in failed: ", body.get_string_from_utf8())

func get_identity_id(id_token: String):
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_get_id_completed.bind(id_token))
	
	var endpoint = "https://cognito-identity." + REGION + ".amazonaws.com/"
	var headers = ["Content-Type: application/x-amz-json-1.1", "X-Amz-Target: AWSCognitoIdentityService.GetId"]
	var body = JSON.stringify({
			"IdentityPoolId": IDENTITY_POOL_ID,
			"Logins": {"cognito-idp." + REGION + ".amazonaws.com/" + USER_POOL_ID: id_token}
			},"\t")

	http.request(endpoint, headers, HTTPClient.METHOD_POST, body)

func _on_get_id_completed(result, response_code, headers, body, id_token):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		var identity_id = response["IdentityId"]
		get_credentials(identity_id, id_token)   #Next step
	else:
		print("Get ID failed: ", body.get_string_from_utf8())

func get_credentials(identity_id: String, id_token: String):
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_get_creds_completed)
	
	var endpoint = "https://cognito-identity." + REGION + ".amazonaws.com/"
	var headers = ["Content-Type: application/x-amz-json-1.1", "X-Amz-Target: AWSCognitoIdentityService.GetCredentialsForIdentity"]
	var body = JSON.stringify({
		  "IdentityId": identity_id,
		  "Logins": {"cognito-idp." + REGION + ".amazonaws.com/" + USER_POOL_ID: id_token}
		},"\t")

	http.request(endpoint, headers, HTTPClient.METHOD_POST, body)

func _on_get_creds_completed(result, response_code, headers, body):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		temp_access_key = response["Credentials"]["AccessKeyId"]
		temp_secret_key = response["Credentials"]["SecretKey"]
		temp_session_token = response["Credentials"]["SessionToken"]
		print("Temp creds obtained!")
		var http = HTTPRequest.new()
		add_child(http)
		http.connect("request_completed", spawn_item_test)
		http.request(
		$SubViewportContainer.generate_presigned_url("game-view-marketplace-test","assets/models/monkeytest.fbx",temp_access_key,temp_secret_key,REGION,"GET",temp_session_token)
		)   #Now use these to generate pre-signed URLs
	else:
		print("Get creds failed: ", body.get_string_from_utf8())
		
func spawn_item_test(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		print("Download successful! File size: ", body.size(), " bytes")
		# Save the downloaded file to the user data directory.
		var file = FileAccess.open("res://testItem.fbx", FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			print("File saved to res:///testItem.fbx")
			_load_item((file.get_path()));
			# You can now load the FBX file into your scene.
		else:
			print("Error saving file.")
	else:
		print("Download failed. Response code: ", response_code)
		
func _load_item(path : String) -> void:
	if not FileAccess.file_exists(path):
		print("Error: File not found at ", path)
		return
	
	# Load the resource from the user data path.
	var loaded_model = load(path)
	
	
	if loaded_model:
		# Check if the loaded resource is a valid 3D model scene.
		if loaded_model is PackedScene:
			var model_instance = loaded_model.instantiate()
			add_child(model_instance)
			print("Model loaded and added to scene.")
		else:
			print("Error: The loaded file is not a valid 3D scene.")
	else:
		print("Error: Failed to load the model.")
