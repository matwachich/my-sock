#include "mysock.bi"

#define CRLF chr(13, 10)

declare sub onRecv (myCln as myCln_t ptr, data_ as ubyte ptr, data_len as uinteger)

dim shared as byte keep_going = 1

MySock_Startup()

' Create a client
dim shared cln as myCln_t ptr
cln = MyCln_Create("www.freebasic.net", 80, MYSOCK_PROT_IPV4)
MyCln_SetCallbacks(cln, 0, cast(myClnOnRecvProc, @onRecv))

' Connect
if MyCln_Connect(cln, 5) = 0 then print "Connection timed out!": sleep: end
print "Connected to "; MyCln_GetSrvIpStr(cln, 1)

' Send HTTP request
dim as string request = _
	"GET / HTTP/1.1" + CRLF + _
	"Host: www.freebasic.net" + CRLF + _
	"Accept: text/html" + CRLF + _
	"Connection: Close" + CRLF + _
	"User-Agent: My-Sock" + CRLF + CRLF
print "Sending request"
print request
MyCln_Send(cln, strptr(request), len(request))
print

' Wait for response, with a time out
dim shared t as double
t = timer()

while keep_going = 1
	MyCln_Process(cln)
	sleep 100
	' ---
	if timer() - t >= 10 then
		print "No response from the server"
		exit while
	end if
wend

MyCln_Destroy(cln)
MySock_Shutdown()

print "END"
sleep

' ---------------------------------------------------------------------------- '

sub onDisconnect (myCln as myCln_t ptr)
	' when the server closes the connection, then exit
	if myCln = cln then keep_going = 0
end sub

sub onRecv (myCln as myCln_t ptr, data_ as ubyte ptr, data_len as uinteger)
	' data received, re-init the timer
	t = timer()
	' ---
	print "Received data"
	print str(*cast(zstring ptr, data_))
end sub
