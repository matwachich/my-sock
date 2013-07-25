#include "file.bi"

#include "mysock.bi"

' change this port if you already have a HTTP server runing on your machine (wamp ...)
#define HTTP_PORT 8080

' usefull macro
#define CRLF chr(13, 10)

dim shared as byte _keep_going_ = 1

' ---------------------------------------------------------------------------- '

' Server callbacks
declare sub onConnect (mySrv as mySrv_t ptr, peer_id as integer)
declare sub onDisconnect (mySrv as mySrv_t ptr, peer_id as integer)
declare sub onRecv (mySrv as mySrv_t ptr, peer_id as integer, data_ as ubyte ptr, data_len as uinteger)

' Usefull functions
declare sub reply_to_request (mySrv as mySrv_t ptr, peer_id as integer, byref ressource as string, byref mime_type as string)
declare sub not_found (mySrv as mySrv_t ptr, peer_id as integer)
declare sub bad_request (mySrv as mySrv_t ptr, peer_id as integer)
declare function ConvertReq2FilePath (byref req as string) as string
declare function FileRead (byref file_name as string) as string

' ---------------------------------------------------------------------------- '

' Init the library
MySock_Startup()

' Create the server
dim as mySrv_t ptr mySrv = MySrv_Create(50, MYSOCK_PROT_IPV4)
MySrv_SetCallbacks(mySrv, @onConnect, @onDisconnect, @onRecv) ' just ignore compiler warnings

' Start the server
if MySrv_Start(mySrv, HTTP_PORT) = 0 then print "Unable to start server (check if port ";HTTP_PORT;" is free)": sleep: end

print "Web server is runing on port ";HTTP_PORT

' Main loop
while _keep_going_ = 1
	MySrv_Process(mySrv)
	sleep 100
wend

print "Web server is shutting down"

MySrv_Destroy(mySrv)
MySock_Shutdown()

print "END"
sleep

' ---------------------------------------------------------------------------- '

' Just notif about new client
sub onConnect (mySrv as mySrv_t ptr, peer_id as integer)
	print "New client connected from "; MySrv_PeerGetAddrStr(mySrv, peer_id, 1)
end sub

' Just notif about lost client
sub onDisconnect (mySrv as mySrv_t ptr, peer_id as integer)
	print "Client disconnected from "; MySrv_PeerGetAddrStr(mySrv, peer_id, 1)
end sub

' Handle incoming requests from the browser
sub onRecv (mySrv as mySrv_t ptr, peer_id as integer, data_ as ubyte ptr, data_len as uinteger)
	' convert to string
	dim as string req = *cast(zstring ptr, data_)
	' get first line
	req = left(req, instr(req, CRLF))
	' check if it's a GET request
	if left(req, 4) <> "GET " then
		' only GET is supported
		bad_request(mySrv, peer_id)
	end if
	' extracte the requested ressource
	req = mid(req, 5, instr(req, "HTTP/") - 6)
	' ---
	if left(req, 1) <> "/" then req = "/" + req
	' disallow going back a folder
	if instr(req, "/.") then
		bad_request(mySrv, peer_id)
		return
	end if
	if req = "/" then req += "index.html"
	' ---
	' navigate to "localhost:HTTP_PORT/~close_server" to close the web server
	if req = "/~close_server" then
		print MySrv_PeerGetAddrStr(mySrv, peer_id, 1); " issued a close order!"
		_keep_going_ = 0
		return
	end if
	' ---
	' handle request
	dim as string extension, mime_type
	extension = right(req, len(req) - instrrev(req, "."))
	select case extension
		case "html", "htm"
			mime_type = "text/html"
		case "css"
			mime_type = "text/css"
		case "jpg", "jpeg"
			mime_type = "image/jpeg"
		case "png"
			mime_type = "image/png"
		case else
			mime_type = "application/octet-stream"
	end select
	' ---
	print MySrv_PeerGetAddrStr(mySrv, peer_id, 1);" requested: ";req;" (";mime_type;")"
	' ---
	reply_to_request(mySrv, peer_id, ConvertReq2FilePath(req), mime_type)
end sub

' ---------------------------------------------------------------------------- '

sub reply_to_request (mySrv as mySrv_t ptr, peer_id as integer, byref ressource as string, byref mime_type as string)
	' file not found => 404!
	if not fileexists(ressource) then
		not_found(mySrv, peer_id)
		return
	end if
	' ---
	print MySrv_PeerGetAddrStr(mySrv, peer_id, 1); " - OK"
	' ---
	' read file content
	dim as string content = FileRead(ressource)
	' ---
	' build the HTTP response
	dim as string response = _
		"HTTP/1.1 200 OK" + CRLF + _
		"Content-Type: " + mime_type + CRLF + _
		"Content-Lenght: " + str(len(content)) + CRLF + CRLF + _
		content
	' ---
	' send data
	MySrv_PeerSend(mySrv, peer_id, cast(ubyte ptr, strptr(response)), len(response))
	' ---
	MySrv_Close(mySrv, peer_id)
end sub

sub not_found (mySrv as mySrv_t ptr, peer_id as integer)
	print MySrv_PeerGetAddrStr(mySrv, peer_id, 1); " - Not Found!"
	' ---
	dim as string response = "<h3>404 - Not found</h3><p>The server was unable to find the requested ressource</p>"
	response = _
		"HTTP/1.1 404 not-found" + CRLF + _
		"Content-Type: text/HTML" + CRLF + _
		"Content-Length: " + str(len(response)) + CRLF + CRLF + response
	' ---
	MySrv_PeerSend(mySrv, peer_id, cast(ubyte ptr, strptr(response)), len(response))
	MySrv_Close(mySrv, peer_id)
end sub

sub bad_request (mySrv as mySrv_t ptr, peer_id as integer)
	print MySrv_PeerGetAddrStr(mySrv, peer_id, 1); " - Bad request!"
	' ---
	dim as string response = "<h3>400 - Bad request</h3><p>Your browser issued a request that the server was unable to understand</p>"
	response = _
		"HTTP/1.1 400 bad-request" + CRLF + _
		"Content-Type: text/HTML" + CRLF + _
		"Content-Length: " + str(len(response)) + CRLF + CRLF + response
	' ---
	MySrv_PeerSend(mySrv, peer_id, cast(ubyte ptr, strptr(response)), len(response))
	MySrv_Close(mySrv, peer_id)
end sub

' ---------------------------------------------------------------------------- '

function replace(byref txt as string, byref fnd as string, byref rep as string) as string
	dim as string txt2 = txt
	dim as integer fndlen = len(fnd), replen = len(rep)
	
	dim as integer i = instr(txt2, fnd)
	while i
		txt2 = left(txt2, i - 1) & rep & mid(txt2, i + fndlen)
		i = instr(i + replen, txt2, fnd)
	wend

	return txt2
end function

function ConvertReq2FilePath (byref req as string) as string
	#ifdef __FB_WIN32__
	dim as string path = exepath() + "\www" + req
	path = replace(path, "/", "\")
	return path
	#endif
	' I have no experience in Linux programming, but I think this will do it ;)
	#ifdef __FB_LINUX__
	return exepath() + "/www" + req
	#endif
end function

function FileRead (byref file_name as string) as string
	dim as integer ff = freefile()
	open file_name for binary access read as #ff
	dim as string buffer = string(FileLen(file_name) + 1, 0)
	get #ff, 1, buffer
	close #ff
	return buffer
end function
