#include "mysock.bi"

' This example will connect to a listening server, receive data from it,
' and exit when the server drops the connection
'
' Run tcp_listen.bas befor runing this example

#define PORT 14523

MySock_Startup()

dim as MYSOCK sock = MyTcp_Connect("localhost", PORT, MYSOCK_PROT_IPV4, 5)
if sock = -1 then print "Unable to connect to the server": sleep: end

print "Connected to "; MySock_SocketGetPeerAddrStr(sock, 1)
print "Waiting for data ..."

dim as integer ret
dim as zstring * 256 buff
do
	ret = MyTcp_Recv(sock, @buff, 256)
	if ret = -1 then exit do
	
	if ret > 0 then
		print buff
	end if
loop

MyTcp_CloseSocket(sock)
MySock_Shutdown()

print "END"
sleep