#include "mysock.bi"

declare sub onConnect (mySrv as mySrv_t ptr, peer_id as integer)
declare sub onDisconnect (mySrv as mySrv_t ptr, peer_id as integer)
declare sub onRecv (mySrv as mySrv_t ptr, peer_id as integer, data_ as ubyte ptr, data_len as uinteger)

' ---------------------------------------------------------------------------- '
' Launche this server, and then simple_cln.exe
' The client will connect to the server, send a couple of messages
' and then disconnect, which will lead the server to shutdown
' ---------------------------------------------------------------------------- '

dim shared as integer keep_going = 1

' Init the library
MySock_Startup()

' Create a server
dim as mySrv_t ptr srv = MySrv_Create(10, MYSOCK_PROT_IPV4)
' Set its callbacks
MySrv_SetCallbacks( _
    srv, _
    cast(mySrvOnConnectProc,	@onConnect), _
    cast(mySrvOnDisconnectProc,	@onDisconnect), _
    cast(mySrvOnPacketRecvProc,	@onRecv), _
    0, 0 _
)
' And start it. It's only here that the listening socket will be bound
' So you should check this function for succes. Otherwise, the most likely reason
'	is that the port is not free
MySrv_Start(srv, 8080)

' Call the process function in loop
do
    MySrv_Process(srv)
    sleep 100
loop until keep_going = 0

' Destroy the server
' This will also disconnect all connected peers, and call the MySrv_Process function
'	so that the peers disconnection will be notified by calling each time the
'	onDisconnect function
MySrv_Destroy(srv)

' Shutdown the library
MySock_Shutdown()

print "END"
sleep

' ---------------------------------------------------------------------------- '

' Called when a peer connects to the server
sub onConnect (mySrv as mySrv_t ptr, peer_id as integer)
    ' Just notifiy
    print "+ Peer: "; peer_id; " [" ; MySrv_PeerGetAddrStr(mySrv, peer_id, 1) ; "]"
end sub

' Called when a peer disconnects from the server
sub onDisconnect (mySrv as mySrv_t ptr, peer_id as integer)
    ' Notifiy
    print "- Peer: "; peer_id; " [" ; MySrv_PeerGetAddrStr(mySrv, peer_id, 1) ; "]"
    ' Close the server when a client disconnects
    keep_going = 0
end sub

' Called when data is received from a connected peer
sub onRecv (mySrv as mySrv_t ptr, peer_id as integer, data_ as ubyte ptr, data_len as uinteger)
    ' Get a ZString pointer
    dim as zstring ptr str_data = cast(zstring ptr, data_)
    ' print the received data
    print "> Data from peer " ; peer_id ; ":"
    print "	"; str(*str_data)
end sub
