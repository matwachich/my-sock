#ifdef __FB_WIN32__
	'#define UNICODE
	'#define WIN32_LEAN_AND_MEAN
	'#include "windows.bi"
	#include "win\ws2tcpip.bi"
	'type socklen_t as integer
	
	'/// Part of mstcpip.h ///'
	#define SIO_KEEPALIVE_VALS	_WSAIOW(IOC_VENDOR,4)
	type tcp_keepalive
		as ulong onoff
		as ulong keepalivetime
		as ulong keepaliveinterval
	end type
	'/// ///'
#else
#error MySock is designed for windows only!
#endif

#include "mysock.bi"
#include "funcs.bi"

' ---------------------------------------------------------------------------- '
' internal macros

#define CLN_CONNECTED(cln) cln->sock <> INVALID_SOCKET

' ---------------------------------------------------------------------------- '
' internal functions

' ---------------------------------------------------------------------------- '
' data structures

type _myCln_t
	as SOCKET sock
	as zstring ptr host ' host passed to MyCln_Create
	as zstring * INET6_ADDRSTRLEN ip ' resolved ip when MyCln_Connect
	as ushort port
	as protocol_e protocol
	
	as ubyte ptr recv_buff
	as uinteger recv_buff_len
	
	as uinteger keepalive_timeout
	as uinteger keepalive_interval
	
	as myClnOnDisconnectProc onDisconnect
	as myClnOnRecvProc onRecv
	
	as any ptr user_data
end type

' ---------------------------------------------------------------------------- '

extern "C"

' ---------------------------------------------------------------------------- '

function MyCln_Create (host as zstring, port as ushort, protocol as protocol_e) as myCln_t ptr MYSOCK_EXPORT
	dim as myCln_t ptr myCln = callocate(1, sizeof(myCln_t))
	if myCln = 0 then return 0
	' ---
	myCln->sock = INVALID_SOCKET
	myCln->port = port
	' ---
	myCln->host = callocate(len(host) + 1, sizeof(zstring))
	if myCln->host = 0 then deallocate(myCln): return 0
	*(myCln->host) = host
	' ---
	myCln->ip = ""
	myCln->protocol = prot2af(protocol)
	' ---
	myCln->recv_buff = 0	' allocated on succesfull connect
	myCln->recv_buff_len = 0
	' ---
	myCln->keepalive_timeout = 0
	myCln->keepalive_interval = 0
	' ---
	myCln->onDisconnect = 0
	myCln->onRecv = 0
	' ---
	return myCln
end function

function MyCln_Destroy (myCln as myCln_t ptr) as integer MYSOCK_EXPORT
	MyCln_Close(myCln)
	' ---
	if myCln->host <> 0 then deallocate(myCln->host)
	if myCln->recv_buff <> 0 then deallocate(myCln->recv_buff)
	' ---
	deallocate(myCln)
	' ---
	return 1
end function

function MyCln_Connect (myCln as myCln_t ptr, timeout as uinteger) as integer MYSOCK_EXPORT
	if CLN_CONNECTED(myCln) then return 0
	' ---
	dim as addrinfo hints: clear(hints, 0, sizeof(hints))
	dim as addrinfo ptr list
	
	hints.ai_family = myCln->protocol
	hints.ai_socktype = SOCK_STREAM
	
	if getaddrinfo(myCln->host, str(myCln->port), @hints, @list) <> 0 then
		#ifdef MYSOCK_DEBUG
		print "! MyCln_Connect failed - (getaddrinfo failed - err" ; WSAGetLastError() ; ")"
		#endif
		return 0
	end if
	if list = 0 then
		#ifdef MYSOCK_DEBUG
		print "! MyCln_Connect failed - (getaddrinfo returned empty list - err" ; WSAGetLastError() ; ")"
		#endif
		return 0
	end if
	
	dim as ulong yes = 1
	dim as timeval tv
	dim as fd_set set
	
	do
		myCln->sock = socket_(list->ai_family, list->ai_socktype, list->ai_protocol)
		if myCln->sock = INVALID_SOCKET then goto try_next
		
		if ioctlsocket(myCln->sock, FIONBIO, @yes) <> 0 then goto try_next		
		' /// timeout connect /// '
		if connect(myCln->sock, list->ai_addr, list->ai_addrlen) <> 0 and WSAGetLastError() <> WSAEWOULDBLOCK then goto try_next
		
		tv.tv_sec = timeout
		tv.tv_usec = 0
		
		FD_ZERO(@set)
		FD_SET_(myCln->sock, @set)
		
		if select_(0, 0, @set, 0, @tv) <= 0 then
			#ifdef MYSOCK_DEBUG
			print "! MyCln_Connect - select timedout"
			#endif
			goto try_next
		end if
		
		' /// /// '
		sockaddr2ipport(cast(sockaddr_storage ptr, list->ai_addr), list->ai_addrlen, myCln->ip, INET6_ADDRSTRLEN, 0)
		freeaddrinfo(list)
		exit do
		
		try_next:
		if myCln->sock <> INVALID_SOCKET then closesocket(myCln->sock)
		myCln->sock = INVALID_SOCKET
		' ---
		list = list->ai_next
		if list = 0 then
			#ifdef MYSOCK_EXPORT
			print "! MyCln_Connect failed - (unable to create/connect socket - err " ; WSAGetLastError() ; ")"
			#endif
			freeaddrinfo(list)
			return 0
		end if
	loop
	
	myCln->recv_buff = callocate(DEFAULT_RECV_BUFFER_LEN, sizeof(byte))
	myCln->recv_buff_len = DEFAULT_RECV_BUFFER_LEN
	
	#ifdef MYSOCK_DEBUG
	print "> Client @"; myCln; " connected to "; str(myCln->ip); ":"; myCln->port
	#endif
	return 1
end function

function MyCln_Close (myCln as myCln_t ptr) as integer MYSOCK_EXPORT
	if not CLN_CONNECTED(myCln) then return 0
	
	if closesocket(myCln->sock) = 0 then return 1
	return 0
end function

function MyCln_IsConnected (myCln as myCln_t ptr) as integer MYSOCK_EXPORT
	if CLN_CONNECTED(myCln) then return 1
	return 0
end function

sub MyCln_SetProtocol (myCln as myCln_t ptr, protocol as protocol_e) MYSOCK_EXPORT
	myCln->protocol = prot2af(protocol)
end sub

function MyCln_GetProtocol (myCln as myCln_t ptr) as integer MYSOCK_EXPORT
	return af2prot(myCln->protocol)
end function

sub MyCln_SetHost (myCln as myCln_t ptr, host as zstring, port as ushort) MYSOCK_EXPORT
	if myCln->host <> 0 then deallocate(myCln->host)
	dim as integer l = len(host)
	myCln->host = callocate(l + 1, sizeof(zstring))
	if myCln->host = 0 then return
	*(myCln->host) = host
	' ---
	myCln->port = port
end sub

sub MyCln_GetHost (myCln as myCln_t ptr, host as zstring, host_len as uinteger, port as ushort ptr) MYSOCK_EXPORT
	host = left(*(myCln->host), host_len - 1)
	if port <> 0 then *port = myCln->port
end sub

function MyCln_GetHostStrIp (myCln as myCln_t ptr, port as ushort ptr) as string MYSOCK_EXPORT
	if port <> 0 then *port = myCln->port
	return str(*myCln->host)
end function

function MyCln_GetHostStrIpPort (myCln as myCln_t ptr) as string MYSOCK_EXPORT
	return str(*myCln->host) + ":" + str(myCln->port)
end function

sub MyCln_GetSrvIp (myCln as myCln_t ptr, ip as zstring, ip_len as uinteger) MYSOCK_EXPORT
	ip = left(myCln->ip, ip_len - 1)
end sub

function MyCln_GetSrvIpStrIp (myCln as myCln_t ptr) as string MYSOCK_EXPORT
	return str(myCln->ip)
end function

sub MyCln_SetCallbacks (myCln as myCln_t ptr, onDisconnect as myClnOnDisconnectProc, onRecv as myClnOnRecvProc) MYSOCK_EXPORT
	print onDisconnect, onRecv
	myCln->onDisconnect = onDisconnect
	print 1
	myCln->onRecv = onRecv
	print 2
end sub

sub MyCln_Process (myCln as myCln_t ptr) MYSOCK_EXPORT
	if not CLN_CONNECTED(myCln) then return
	' ---
	dim as byte disconnect = 0
	dim as integer ret = recv(myCln->sock, myCln->recv_buff, myCln->recv_buff_len, 0)
	select case ret
		case is > 0
			if myCln->onRecv then myCln->onRecv(myCln, myCln->recv_buff, myCln->recv_buff_len)
		case 0
			disconnect = 1
		case -1
			if WSAGetLastError() <> WSAEWOULDBLOCK then
				disconnect = 1
			end if
	end select
	' ---
	if disconnect then
		if myCln->onDisconnect then myCln->onDisconnect(myCln)
		' ---
		closesocket(myCln->sock)
		myCln->sock = INVALID_SOCKET
		' ---
		if myCln->recv_buff <> 0 then deallocate(myCln->recv_buff): myCln->recv_buff = 0
		myCln->recv_buff_len = 0
	end if
end sub

function MyCln_Send (myCln as myCln_t ptr, data_ as byte ptr, data_len as uinteger) as integer MYSOCK_EXPORT
	if not CLN_CONNECTED(myCln) then return 0
	
	#ifdef BUFFERED ' send first packet with data_ len
	if send(myCln->sock, cast(byte ptr, @data_len), sizeof(data_len), 0) <> sizeof(data_len) then return -1
	#endif
	
	dim as integer total = 0, remain = data_len, n = 0

	do while total < data_len
		n = send(myCln->sock, @data_[total], remain, 0)
		if n = -1 and WSAGetLastError() <> WSAEWOULDBLOCK then return -1
		total += n
		remain -= n
	loop

	return total
end function

function MyCln_SetBuffLen (myCln as myCln_t ptr, buff_len as uinteger) as integer MYSOCK_EXPORT
	myCln->recv_buff = reallocate(myCln->recv_buff, buff_len)
	if myCln->recv_buff = 0 then return 0
	
	myCln->recv_buff_len = buff_len
	return buff_len
end function

function MyCln_GetBuffLen (myCln as myCln_t ptr) as uinteger MYSOCK_EXPORT
	return myCln->recv_buff_len
end function

function MyCln_SetKeepAlive (myCln as myCln_t ptr, timeout as uinteger, interval as uinteger) as integer MYSOCK_EXPORT
	dim as tcp_keepalive struct
	dim as DWORD ret = 0
	if timeout <> 0 and interval <> 0 then
		struct.onoff = 1
		struct.keepalivetime = timeout * 1000
		struct.keepaliveinterval = interval * 1000
	else
		struct.onoff = 0
		struct.keepalivetime = 0
		struct.keepaliveinterval = 0
	end if
	if WSAIoctl(myCln->sock, SIO_KEEPALIVE_VALS, @struct, sizeof(struct), 0, 0, @ret, 0, 0) <> 0 then
		#ifdef MYSOCK_DEBUG
		print "! WSAIoctl failed setting SIO_KEEPALIVE_VALS! (err " ; WSAGetLastError() ; ")"
		#endif
		return 0
	else ' update peer's values
		myCln->keepalive_timeout = timeout
		myCln->keepalive_interval = interval
		' ---
		return 1
	end if
end function

sub MyCln_GetKeepAlive (myCln as myCln_t ptr, timeout as uinteger ptr, interval as uinteger ptr) MYSOCK_EXPORT
	if timeout <> 0 then *timeout = myCln->keepalive_timeout
	if interval <> 0 then *interval = myCln->keepalive_interval
end sub

sub MyCln_SetUserData (myCln as myCln_t ptr, user_data as any ptr) MYSOCK_EXPORT
	myCln->user_data = user_data
end sub

function MyCln_GetUserData (myCln as myCln_t ptr) as any ptr MYSOCK_EXPORT
	return myCln->user_data
end function

' ---------------------------------------------------------------------------- '

end extern

' ---------------------------------------------------------------------------- '
