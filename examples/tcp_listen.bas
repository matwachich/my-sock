#include "mysock.bi"

' This example will run a simple listening TCP socket.
' It will wait for a peer to connect, send it a message and exit.
'
' Run this example, then run tcp_connect.bas

#define PORT 14523

MySock_Startup()

dim as MYSOCK sock = MyTcp_Listen(PORT, MYSOCK_PROT_IPV4, 5)
if sock = -1 then print "Unable to open listening socket (check the port)": sleep: end
print "Listening for TCP connections on "; MySock_SocketGetAddrStr(sock, 1)

dim as MYSOCK client = -1
do
	client = MyTcp_Accept(sock)
	sleep 250
loop until client <> -1
print "Client connected from "; MySock_SocketGetPeerAddrStr(client, 1)

print MyTcp_Send(client, cast(ubyte ptr, @"Hello! And welcome the server!"), len("Hello! And welcome the server!")); _
	" bytes sent"

MyTcp_CloseSocket(client)
MyTcp_CloseSocket(sock)
MySock_Shutdown()

print "END"
sleep
