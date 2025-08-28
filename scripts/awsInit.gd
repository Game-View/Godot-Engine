extends Node

const REGION = "us-east-1"   #Your region
const USER_POOL_ID = "us-east-1_1i60DZnE2"   #Your user pool ID
const CLIENT_ID = "3c9h80tqv3er2rgi388gl0cnt1"   #App client ID
const IDENTITY_POOL_ID = "us-east-1:eb5e7e93-8fd8-4f80-8434-85807e43992a"   #Identity pool ID
const CLIENT_SECRET = "pvj4igkvm1cmrslmfihqcr7jnkrj51j1oeosg3eh5h3rmrjf635"


var temp_access_key: String
var temp_secret_key: String
var temp_session_token: String

var stored_username : String
var stored_password : String

#Secrete hash for cognito login
func generate_secret_hash(username: String, client_id: String, client_secret: String) -> String:
	var message_bytes = (username + client_id).to_utf8_buffer()
	var key_bytes = client_secret.to_utf8_buffer()
	var hmac_digest = Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key_bytes, message_bytes)
	var base64_digest = Marshalls.raw_to_base64(hmac_digest)
	return base64_digest

#Sign in for cognito
#NOTE callback travels all the way to _on_get_creds_completed
func sign_in(username: String = stored_username, password: String = stored_password, callback : Callable = Callable()):
	if(not username or not password):
		print("Sign in failed for ", username)
		return
	elif(password!=stored_password):
		stored_password = password
		stored_username = username
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_sign_in_completed.bind(callback,http)) #next step
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

#Sign in request completed
func _on_sign_in_completed(result, response_code, headers, body, callback : Callable = Callable(),httpRequest = null):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		var id_token = response["AuthenticationResult"]["IdToken"]
		get_identity_id(id_token, callback)  #Next step
	else:
		print("Sign-in failed: ", body.get_string_from_utf8())
	if(httpRequest):
		httpRequest.queue_free()

#Get Identity from cognito sign in
func get_identity_id(id_token: String, callback : Callable = Callable()):
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_get_id_completed.bind(id_token,callback,http)) #next step
	
	var endpoint = "https://cognito-identity." + REGION + ".amazonaws.com/"
	var headers = ["Content-Type: application/x-amz-json-1.1", "X-Amz-Target: AWSCognitoIdentityService.GetId"]
	var body = JSON.stringify({
			"IdentityPoolId": IDENTITY_POOL_ID,
			"Logins": {"cognito-idp." + REGION + ".amazonaws.com/" + USER_POOL_ID: id_token}
			},"\t")

	http.request(endpoint, headers, HTTPClient.METHOD_POST, body)

#Get Identity completed
func _on_get_id_completed(result, response_code, headers, body, id_token, callback : Callable = Callable(),httpRequest = null):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		var identity_id = response["IdentityId"]
		get_credentials(identity_id, id_token,callback)   #Next step
		
	else:
		print("Get ID failed: ", body.get_string_from_utf8())
	if(httpRequest):
		httpRequest.queue_free()

#Get Credentials for user
func get_credentials(identity_id: String, id_token: String, callback : Callable = Callable()):
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", _on_get_creds_completed.bind(callback,http)) #next step
	
	var endpoint = "https://cognito-identity." + REGION + ".amazonaws.com/"
	var headers = ["Content-Type: application/x-amz-json-1.1", "X-Amz-Target: AWSCognitoIdentityService.GetCredentialsForIdentity"]
	var body = JSON.stringify({
		  "IdentityId": identity_id,
		  "Logins": {"cognito-idp." + REGION + ".amazonaws.com/" + USER_POOL_ID: id_token}
		},"\t")

	http.request(endpoint, headers, HTTPClient.METHOD_POST, body)

#Get Credentials Completed
func _on_get_creds_completed(result, response_code, headers, body, callback : Callable = Callable(),httpRequest = null):
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
	if(httpRequest):
		httpRequest.queue_free()
	
#Get Presigned 'GET' url from presignUrl.gd
func _get_url_from_server(bucket: String, item_path : String, tried : bool = false) -> String:
		var url = Presigned_URL.generate_presigned_url(bucket,item_path,temp_access_key,temp_secret_key,REGION,"GET",temp_session_token)
		##EDIT FOR WHEN URL IS INVALID, MUST CALL FUNCTION THAT CALLED THIS
		##if(!url && !tried):
		##	sign_in(stored_username,stored_password,_get_url_from_server.bind(bucket,item_path,true))
		##	print("Session expired, retrying")
		##elif !url && tried:
		##	print("Session exired, and cannot log back in")
		return url;
