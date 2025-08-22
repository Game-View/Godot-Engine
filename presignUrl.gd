# This script assumes a correct HMAC-SHA256 implementation is available
# as a global function or within a class, which returns raw bytes.

extends Node
# Placeholder for a correct HMAC-SHA256 function that returns a PackedByteArray
# You MUST replace this with a correct implementation from a plugin or a manual
# implementation of RFC 2104.
# A function that takes a key (PackedByteArray) and data (PackedByteArray)
# and returns the HMAC-SHA256 signature as a PackedByteArray.
func generate_hmac_sha256(key: PackedByteArray, message: String) -> String:
	var crypto = Crypto.new()
	var hmac = crypto.hmac_digest(HashingContext.HASH_SHA256, key, message.to_utf8_buffer())
	return hmac.hex_encode()

func compute_sha256(data: String) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data.to_utf8_buffer())
	var hash = ctx.finish()
	return hash.hex_encode()

func generate_presigned_url(bucket: String, object_key: String, access_key: String, secret_key: String, region: String, http_method: String = "GET", session_token: String = "", expires_in: int = 3600) -> String:
	var timestamp = Time.get_datetime_dict_from_system(true)
	var date = "%04d%02d%02d" % [timestamp.year, timestamp.month, timestamp.day]
	var datetime = "%sT%02d%02d%02dZ" % [
		date,
		timestamp.hour,
		timestamp.minute,
		timestamp.second]
	var host = "%s.s3.%s.amazonaws.com" % [bucket, region]
	var canonical_uri = "/" + object_key
	var query_params = "X-Amz-Algorithm=AWS4-HMAC-SHA256&" + \
					  "X-Amz-Credential=%s/%s/%s/s3/aws4_request&" % [access_key, date, region] + \
					  "X-Amz-Date=%s&" % datetime + \
					  "X-Amz-Expires=%d" % expires_in
	if session_token != "":
		query_params += "&X-Amz-Security-Token=%s" % session_token.uri_encode()
	query_params += "&X-Amz-SignedHeaders=host"
	var canonical_headers = "host:%s\n" % host
	var payload_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" # Empty payload SHA256
	var canonical_request = "%s\n%s\n%s\n%s\nhost\n%s" % [
		http_method,
		canonical_uri,
		query_params,
		canonical_headers,
		payload_hash]
	
	var algorithm = "AWS4-HMAC-SHA256"
	var credential_scope = "%s/%s/s3/aws4_request" % [date, region]
	var canonical_request_hash = compute_sha256(canonical_request)
	var string_to_sign = "%s\n%s\n%s\n%s" % [
		algorithm,
		datetime,
		credential_scope,
		canonical_request_hash]

	var date_key = generate_hmac_sha256(("AWS4" + secret_key).to_utf8_buffer(), date)
	var date_region_key = generate_hmac_sha256(date_key.to_utf8_buffer(), region)
	var date_region_service_key = generate_hmac_sha256(date_region_key.to_utf8_buffer(), "s3")
	var signing_key = generate_hmac_sha256(date_region_service_key.to_utf8_buffer(), "aws4_request")
	var signature = generate_hmac_sha256(signing_key.to_utf8_buffer(), string_to_sign)

	var presigned_url = "https://%s/%s?%s&X-Amz-Signature=%s" % [
		host,
		object_key,
		query_params,
		signature]
	print(presigned_url)
	return presigned_url

# Helper function for SHA-256 hash
func sha256(data: PackedByteArray) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()
