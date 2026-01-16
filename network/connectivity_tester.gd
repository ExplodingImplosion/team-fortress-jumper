const Network = Quack.Network
const internet_connectivity_tester_urls: PackedStringArray = ["1.1.1.1","8.8.8.8","www.google.com","www.example.com"]
const ConnectivityTester = Network.ConnectivityTester

static func check_http_client_connection(http_client: HTTPClient, url_idx: int, attempt_num: int) -> void:
	var poll: Error = http_client.poll()
	assert(poll == OK or poll == ERR_CANT_RESOLVE, "poll should work... got %s instead."%error_string(poll))
	match get_http_client_connection_result_from_status(http_client.get_status()):
		HTTPCLIENTCONNECTIONSTATUS.CONNECTING:
			if attempt_num >= MAX_HTTP_CONNECTION_ATTEMPTS:
				if url_idx < internet_connectivity_tester_urls.size() - 1:
					print("Connecting to %s unsuccessful after %s attempts."%[
						internet_connectivity_tester_urls[url_idx],MAX_HTTP_CONNECTION_ATTEMPTS
					])
					try_connecting_to_host(http_client,url_idx+1,0)
				else:
					Network.is_connected_to_internet = false
					print("Connecting to %s unsuccessful after %s attempts. All connection attempts failed."%[
						internet_connectivity_tester_urls[url_idx],MAX_HTTP_CONNECTION_ATTEMPTS
					])
					http_client.close()
			else:
				wait_for_connection(http_client,url_idx,attempt_num+1)
		HTTPCLIENTCONNECTIONSTATUS.CONNECTED:
			Network.is_connected_to_internet = true
			print("Connected to %s on attempt %s."%[internet_connectivity_tester_urls[url_idx],attempt_num])
			http_client.close()
		HTTPCLIENTCONNECTIONSTATUS.FAILED:
			if url_idx < internet_connectivity_tester_urls.size() - 1:
				print("Connecting to %s failed on attempt %s."%[
					internet_connectivity_tester_urls[url_idx],
					attempt_num+1])
				try_connecting_to_host(http_client,url_idx+1,0)
			else:
				Network.is_connected_to_internet = false
				print("Connecting to %s failed on attempt %s. All connection attempts failed."%[
					internet_connectivity_tester_urls[url_idx],
					attempt_num+1])
				http_client.close()

enum HTTPCLIENTCONNECTIONSTATUS{CONNECTING,CONNECTED,FAILED}

static func get_http_client_connection_result_from_status(status: int) -> int:
	if status == HTTPClient.STATUS_CONNECTED:
		return HTTPCLIENTCONNECTIONSTATUS.CONNECTED
	elif status == HTTPClient.STATUS_CANT_CONNECT or status == HTTPClient.STATUS_CANT_RESOLVE or status == HTTPClient.STATUS_CONNECTION_ERROR or status == HTTPClient.STATUS_DISCONNECTED:
		return HTTPCLIENTCONNECTIONSTATUS.FAILED
	else:
		return HTTPCLIENTCONNECTIONSTATUS.CONNECTING

const MAX_HTTP_CONNECTION_ATTEMPTS = 3

static func try_connecting_to_host(http_client: HTTPClient, url_idx: int, attempt_num: int) -> void:
	var error: Error = http_client.connect_to_host(internet_connectivity_tester_urls[url_idx])
	assert(error == OK,"connect_to_host is supposed to work even if the connection doesn't. got %s instead."%error_string(error))
	wait_for_connection(http_client,url_idx,attempt_num)

static func wait_for_connection(http_client: HTTPClient, url_idx: int, attempt_num: int) -> void:
	prints("HTTPClient attempting to connect to url %s, attempt number %s"%[internet_connectivity_tester_urls[url_idx],attempt_num])
	Quack.connect_to_timer(1.0,check_http_client_connection.bind(http_client,url_idx,attempt_num))

static func test_internet_connection() -> void:
	assert(!internet_connectivity_tester_urls.is_empty(), "internet_connectivity_tester_urls is empty.")
	var http_client := HTTPClient.new()
	try_connecting_to_host(http_client,0,0)

static func get_public_ipv4() -> bool:
	await IPChecker.new().done
	return true

class IPChecker extends Object:
	const MAX_RESPONSE_POLL_ATTEMPTS = 40
	var client := HTTPClient.new()
	signal done
	
	const ipify_url = "https://api.ipify.org"
	func _init() -> void:
		var err := client.connect_to_host(ipify_url)
		assert(err == OK,"connect_to_host is supposed to work even if the connection doesn't. got %s instead."%error_string(err))
		wait_for_ip_response(check_ip_connection,0)
		
	func wait_for_ip_response(callable: Callable, attempt_num: int) -> void:
		prints("%s, attempt number %s"%[callable.get_method(),attempt_num])
		Quack.connect_to_timer(.25,callable.bind(attempt_num))
	
	func on_ipify_request_failure(client: HTTPClient) -> void:
		Network.pub_ipv4 = ""
		print("Connecting to IPify API unsuccessful after %s attempts. All connection attempts failed."%MAX_HTTP_CONNECTION_ATTEMPTS)
		finish()
	
	func finish() -> void:
		client.close()
		done.emit()
		free.call_deferred()
	
	func on_ipify_request_unsuccessful(attempt_num: int, failure_string: String) -> void:
		if attempt_num >= MAX_HTTP_CONNECTION_ATTEMPTS:
			on_ipify_request_failure(client)
		else:
			print(failure_string)
			wait_for_ip_response(check_ip_connection,attempt_num+1)
	
	func check_ip_connection(attempt_num: int) -> void:
		var poll: Error = client.poll()
		assert(poll == OK or poll == ERR_CANT_RESOLVE, "poll should work... got %s instead."%error_string(poll))
		match ConnectivityTester.get_http_client_connection_result_from_status(client.get_status()):
			HTTPCLIENTCONNECTIONSTATUS.CONNECTING:
				on_ipify_request_unsuccessful(attempt_num,"Connecting to IPify API unfinished. Retrying...")
			HTTPCLIENTCONNECTIONSTATUS.CONNECTED:
				print("Connected to IPify API on attempt %s."%attempt_num)
				var err := client.request(HTTPClient.METHOD_GET,ipify_url,[])
				assert(err == OK, "Requesting IPify API returned error %s"%error_string(err))
				wait_for_ip_response(check_ip_response,0)
			HTTPCLIENTCONNECTIONSTATUS.FAILED:
				on_ipify_request_unsuccessful(attempt_num,"Connecting to IPify API failed. Retrying...")
	
	func check_ip_response(num_attempts: int) -> void:
		var poll: Error = client.poll()
		assert(poll == OK or poll == ERR_CANT_RESOLVE, "poll should work... got %s instead."%error_string(poll))
		var status := client.get_status()
		if client.has_response() and status == HTTPClient.STATUS_BODY:
			var code := client.get_response_code()
			if code == HTTPClient.RESPONSE_OK:
				Network.pub_ipv4 = client.read_response_body_chunk().get_string_from_ascii()
				finish()
			else:
				printerr("IP checker request got an invalid response code %s."%code)
				var err := client.request(HTTPClient.METHOD_GET,ipify_url,[])
				assert(err == OK, "Requesting IPify API returned error %s"%error_string(err))
				on_response_unsuccessful(num_attempts)
		elif status == HTTPClient.STATUS_REQUESTING:
			if client.has_response():
				printerr("Status is %s while client says it doesn't have a response."%status)
				on_response_unsuccessful(num_attempts)
			else:
				printerr("Client says it has a response, but status is %s."%status)
				printerr("Response code: %s. Body: %s."%[
					client.get_response_code(),
					client.read_response_body_chunk()
				])
				on_response_unsuccessful(num_attempts)
		elif status != HTTPClient.STATUS_CONNECTED:
			printerr("IP checker encountered a connection issue. (Status %s). Aborting."%status)
			finish()
		else:
			printerr("hmm %s"%get_stack())
			on_response_unsuccessful(num_attempts)
	
	func on_response_unsuccessful(num_attempts: int) -> void:
		if num_attempts >= MAX_RESPONSE_POLL_ATTEMPTS:
			print("IPify timed out.")
			Network.pub_ipv4 = ""
			finish()
		else:
			return wait_for_ip_response(check_ip_response,num_attempts+1)
