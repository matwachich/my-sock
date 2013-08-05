#include "mysock.bi"

declare sub onDisconnect (myCln as myCln_t ptr, partial_data as ubyte ptr, data_len as MYSIZE, excepted_len as MYSIZE)
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
    cast(myClnOnPacketRecvProc, @onRecv), _
    0, 0 _
)

' Connextion attempt, with 5 seconds timeout
if MyCln_Connect(cln, 5) = 0 then
    print "Unable to connect"
    end
end if
print "Connected to "; MyCln_GetSrvIpStr(cln, 1)

' Loop until the server said Hi! (see onRecv function)
print "Awaiting server response ..."
dim shared as byte start_sending = 0
do
    MyCln_Process(cln)
    sleep(100)
loop until start_sending = 1

' Server replied, start sending messages
print "Now sending some messages ..."

' Don't forget to send the ending \0 caracter (len(msg) + 1)
' Because the simple_srv.bas on the other side will simply
' do cast(zstring ptr, data_)
dim as zstring * 100 msg

' We don't call MyCln_Process while sending these messages because we don't except
' any answer from the server. But in practice, you should Process a Client or
' a Server in the main loop of your program

msg = "Hello Server!"
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

' Destroy the client, this function will also disconnect it, and call MyCln_Process() once
' so that the disconnect callback will be trigered
MyCln_Destroy(cln)

' Shutdown the library
MySock_Shutdown()

print "END"
sleep

' ---------------------------------------------------------------------------- '

' Called when a client disconnects
sub onDisconnect (myCln as myCln_t ptr, partial_data as ubyte ptr, data_len as MYSIZE, excepted_len as MYSIZE)
    print "Disconnected!"
end sub

' Called when data is received from the server
sub onRecv (myCln as myCln_t ptr, data_ as ubyte ptr, data_len as uinteger)
    ' Get a ZString pointer
    dim as zstring ptr str_data = cast(zstring ptr, data_)
    ' print the received data
    print "> Data from server: " + str(*str_data)
    ' Indicate that the server said Hi! And start sending messages
    start_sending = 1
end sub
