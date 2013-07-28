#include "mysock.bi"

#define CRLF chr(13, 10)

MySock_Startup()

dim as MYSOCK socket = MyTcp_Connect("www.freebasic.net", 80, MYSOCK_PROT_IPV4, 5)
if socket = -1 then print "Unable to connect to www.freebasic.net": sleep: end
print "Connected to www.freebasic.net"
print MySock_SocketGetAddrStr(socket, 1); " => "; MySock_SocketGetPeerAddrStr(socket, 1)

dim as string request = _
	"GET / HTTP/1.1" + CRLF + _
	"Host: www.freebasic.net" + CRLF + _
	"Accept: text/html" + CRLF + _
	"Connection: Close" + CRLF + _
	"User-Agent: My-Sock" + CRLF + CRLF
print "Sending request:"
print request
MyTcp_Send(socket, cast(ubyte ptr, strptr(request)), len(request))
print

dim as zstring * 1024 recv_buff = ""
dim as integer recv = 0

do
	recv = MyTcp_Recv(socket, cast(ubyte ptr, @recv_buff), 1024)
	if recv = -1 then exit do
	
	if recv > 0 then
		print recv_buff
	end if
loop

MyTcp_CloseSocket(socket)
MySock_Shutdown()

print "END"
sleep