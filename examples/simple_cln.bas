#include "mysock.bi"

declare sub onDisconnect (myCln as myCln_t ptr)
declare sub onRecv (myCln as myCln_t ptr, data_ as ubyte ptr, data_len as uinteger)

' ---------------------------------------------------------------------------- '

' Init the library
MySock_Startup()

' Create a client that connects to localhost:8080
dim as myCln_t ptr cln = MyCln_Create("localhost", 8080, MYSOCK_PROT_IPV4)
' Set it's callbacks
MyCln_SetCallbacks( _
	cln, _
	cast(myClnOnDisconnectProc, @onDisconnect), _
	cast(myClnOnRecvProc, @onRecv) _
)

' Connextion attempt, with 5 seconds timeout
if MyCln_Connect(cln, 5) = 0 then
	print "Unable to connect"
	end
end if

print "Connected to "; MyCln_GetSrvIpStr(cln, 1)
print "Now sending some messages ..."

dim as zstring * 100 msg

msg = "Hello!"
print "1- " ; MyCln_Send(cln, @msg, len(msg) + 1) ; " bytes sent"
sleep 2000

msg = "I'm a peer, and I connected to you, Server!"
print "2- " ; MyCln_Send(cln, @msg, len(msg) + 1) ; " bytes sent"
sleep 2000

msg = "Now I'm going to disconnect"
print "3- " ; MyCln_Send(cln, @msg, len(msg) + 1) ; " bytes sent"
sleep 2000

msg = "Good bye!"
print "4- " ; MyCln_Send(cln, @msg, len(msg) + 1) ; " bytes sent"
sleep 1000

' Note: you see that we don't call the MyCln_Process function since the server will not
' send any data in this example

' Destroy the client, this function will also disconnect it, and call MyCln_Process() once
' so that the disconnect callback will be trigered
MyCln_Destroy(cln)

' Shutdown the library
MySock_Shutdown()

print "END"
sleep

' ---------------------------------------------------------------------------- '

' Called when a client disconnects
sub onDisconnect (myCln as myCln_t ptr)
	print "Disconnected!"
end sub

' Called when data is received from the server
sub onRecv (myCln as myCln_t ptr, data_ as ubyte ptr, data_len as uinteger)
	' The server will send nothing for this example
end sub
