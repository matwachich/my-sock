#include "mysock.bi"

#define CRLF string(1, 13) + string (1, 10)

declare sub onRecv (myCln as myCln_t ptr, data_ as ubyte ptr, data_len as uinteger)

dim shared as byte keep_going = 1

MySock_Startup()

' Create a client
dim as myCln_t ptr cln = MyCln_Create("www.freebasic.net", 80, MYSOCK_PROT_IPV4)
MyCln_SetCallbacks(cln, 0, cast(myClnOnRecvProc, @onRecv))

' Connect
if MyCln_Connect(cln, 5) = 0 then print "Connection timed out!": sleep: end
print "Connected to "; MyCln_GetSrvIpStr(cln, 1)

' Send HTTP request
dim as string request = "get / HTTP/1.1" + CRLF + CRLF
MyCln_Send(cln, strptr(request), len(request))

' Wait for response, with a time out
dim as double t = timer()
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

sub onRecv (myCln as myCln_t ptr, data_ as ubyte ptr, data_len as uinteger)
	print "Received data"
	print str(*cast(zstring ptr, data_))
	' ---
	' Response received, now exit program
	keep_going = 0
end sub