# This script contains the correct implementation for generating a presigned URL for AWS S3
# using the Signature Version 4 (SigV4) authentication process.

# The code fixes flaws in the HMAC-SHA256 calculation and the hashing of the canonical request.

extends Node

# This function computes the SHA256 hash of a string.
func compute_sha256(data: String) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data.to_utf8_buffer())
	var hash = ctx.finish()
	return hash.hex_encode()

# This function correctly implements the HMAC-SHA256 digest using Godot's Crypto class.
# It takes a key and a message (both as PackedByteArray) and returns the signature.
func hmac_sha256_digest(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	var crypto = Crypto.new()
	var hmac = crypto.hmac_digest(HashingContext.HASH_SHA256, key, message)
	return hmac

# This is the main function to generate the presigned URL.
func generate_presigned_url(bucket: String, object_key: String, access_key: String, secret_key: String, region: String, http_method: String = "GET", session_token: String = "", expires_in: int = 3600) -> String:
	# 1. Prepare Date and Host
	var timestamp = Time.get_datetime_dict_from_system(true)
	var date = "%04d%02d%02d" % [timestamp.year, timestamp.month, timestamp.day]
	var datetime = "%sT%02d%02d%02dZ" % [
		date,
		timestamp.hour,
		timestamp.minute,
		timestamp.second]
	var host = "%s.s3.%s.amazonaws.com" % [bucket, region]
	var canonical_uri = "/" + object_key
	
	# 2. Construct the Canonical Request
	var query_dict = {
		"X-Amz-Algorithm": "AWS4-HMAC-SHA256",
		"X-Amz-Credential": access_key + "/" + date + "/" + region + "/s3/aws4_request",
		"X-Amz-Date": datetime,
		"X-Amz-Expires": str(expires_in),
		"X-Amz-SignedHeaders": "host"
	}
	if session_token != "":
		query_dict["X-Amz-Security-Token"] = session_token
	
	var query_keys = query_dict.keys()
	query_keys.sort()
	
	var query_parts = []
	for key in query_keys:
		query_parts.append("%s=%s" % [key.uri_encode(), query_dict[key].uri_encode()])
	var canonical_query_string = "&".join(query_parts)
	
	var canonical_headers = "host:%s\n" % host
	var signed_headers = "host"
	var hashed_payload = "UNSIGNED-PAYLOAD"
	
	var canonical_request = "%s\n%s\n%s\n%s\n%s\n%s" % [
		http_method,
		canonical_uri,
		canonical_query_string,
		canonical_headers,
		signed_headers,
		hashed_payload
	]
	
	# 3. Hash the Canonical Request
	var canonical_request_hash = compute_sha256(canonical_request)

	# 4. Construct the String to Sign
	var string_to_sign = "%s\n%s\n%s\n%s" % [
		"AWS4-HMAC-SHA256",
		datetime,
		date + "/" + region + "/s3/aws4_request", # Credential scope
		canonical_request_hash
	]
	
	# 5. Calculate the Final Signature
	# Key derivation for SigV4
	var k_secret = ("AWS4" + secret_key).to_utf8_buffer()
	var date_key = hmac_sha256_digest(k_secret, date.to_utf8_buffer())
	var date_region_key = hmac_sha256_digest(date_key, region.to_utf8_buffer())
	var date_region_service_key = hmac_sha256_digest(date_region_key, "s3".to_utf8_buffer())
	var signing_key = hmac_sha256_digest(date_region_service_key, "aws4_request".to_utf8_buffer())
	
	# Calculate final signature
	var signature_bytes = hmac_sha256_digest(signing_key, string_to_sign.to_utf8_buffer())
	var signature = signature_bytes.hex_encode()
	
	# 6. Construct the Presigned URL
	var presigned_url = "https://%s/%s?%s&X-Amz-Signature=%s" % [
		host,
		object_key,
		canonical_query_string,
		signature]
	
	print("URL: ", presigned_url)
	return presigned_url
