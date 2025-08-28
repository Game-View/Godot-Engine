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

func sign_in(username: String, password: String, callback : Callable = Callable()):
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_sign_in_completed.bind(callback))
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

func _on_sign_in_completed(result, response_code, headers, body, callback : Callable = Callable()):
	print(body)
	print(body.get_string_from_utf8())
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		var id_token = response["AuthenticationResult"]["IdToken"]
		get_identity_id(id_token, callback)  #Next step
	else:
		print("Sign-in failed: ", body.get_string_from_utf8())

func get_identity_id(id_token: String, callback : Callable = Callable()):
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_get_id_completed.bind(id_token,callback))
	
	var endpoint = "https://cognito-identity." + REGION + ".amazonaws.com/"
	var headers = ["Content-Type: application/x-amz-json-1.1", "X-Amz-Target: AWSCognitoIdentityService.GetId"]
	var body = JSON.stringify({
			"IdentityPoolId": IDENTITY_POOL_ID,
			"Logins": {"cognito-idp." + REGION + ".amazonaws.com/" + USER_POOL_ID: id_token}
			},"\t")

	http.request(endpoint, headers, HTTPClient.METHOD_POST, body)

func _on_get_id_completed(result, response_code, headers, body, id_token, callback : Callable = Callable()):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		var identity_id = response["IdentityId"]
		get_credentials(identity_id, id_token,callback)   #Next step
	else:
		print("Get ID failed: ", body.get_string_from_utf8())

func get_credentials(identity_id: String, id_token: String, callback : Callable = Callable()):
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_get_creds_completed.bind(callback))
	
	var endpoint = "https://cognito-identity." + REGION + ".amazonaws.com/"
	var headers = ["Content-Type: application/x-amz-json-1.1", "X-Amz-Target: AWSCognitoIdentityService.GetCredentialsForIdentity"]
	var body = JSON.stringify({
		  "IdentityId": identity_id,
		  "Logins": {"cognito-idp." + REGION + ".amazonaws.com/" + USER_POOL_ID: id_token}
		},"\t")

	http.request(endpoint, headers, HTTPClient.METHOD_POST, body)

func _on_get_creds_completed(result, response_code, headers, body, callback : Callable = Callable()):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		temp_access_key = response["Credentials"]["AccessKeyId"]
		temp_secret_key = response["Credentials"]["SecretKey"]
		temp_session_token = response["Credentials"]["SessionToken"]
		if(callback.is_valid()):
			callback.call()
		print("Temp creds obtained!")
	else:
		print("Get creds failed: ", body.get_string_from_utf8())
	
func _get_url_from_server(bucket: String, item_path : String) -> String:
		var url = $SubViewportContainer.generate_presigned_url(bucket,item_path,temp_access_key,temp_secret_key,REGION,"GET",temp_session_token)
		return url;
#downloads file and returns path
