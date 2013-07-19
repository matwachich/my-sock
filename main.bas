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

' uncomment the "export" before building a dll
#define MYSOCK_EXPORT export

' ---------------------------------------------------------------------------- '

 extern "C"
 
' ---------------------------------------------------------------------------- '

'' @brief Initiate MySock (WSAStartup)
 '
 ' @return 1 on succes, 0 otherwise
 '/
function MySock_Startup () as integer MYSOCK_EXPORT
	#ifdef __FB_WIN32__
	dim as WSADATA wsa
	if WSAStartup(MAKEWORD(2, 0), @wsa) <> 0 then return 0
	#endif
	return 1
end function

'' @brief Shutdown MySock (WSACleanup)
 '
 ' @return 1 on succes, 0 otherwise
 '/
function MySock_Shutdown () as integer MYSOCK_EXPORT
	#ifdef __FB_WIN32__
	if WSACleanup() <> 0 then return 0
	#endif
	return 1
end function

' ---------------------------------------------------------------------------- '

function MySock_Host2ip (host as zstring, protocol as protocol_e, ip as zstring, ip_len as uinteger) as integer MYSOCK_EXPORT
	dim as addrinfo hints
	clear(hints, 0, sizeof(hints))
	dim as addrinfo ptr list

	select case protocol
		case MYSOCK_PROT_AUTO
			hints.ai_family = AF_UNSPEC
		case MYSOCK_PROT_IPV4
			hints.ai_family = AF_INET
		case MYSOCK_PROT_IPV6
			hints.ai_family = AF_INET6
		case else
			hints.ai_family = AF_UNSPEC
	end select
	hints.ai_socktype = SOCK_STREAM

	if getaddrinfo(host, "80", @hints, @list) <> 0 then return 0
	if list = 0 then return 0
	
	' take the first
	sockaddr2ipport(cast(sockaddr_storage ptr, list->ai_addr), list->ai_addrlen, ip, ip_len, 0)
	
	freeaddrinfo(list)
	
	return 1
end function

function MySock_Host2ipStr (host as zstring, protocol as protocol_e) as string MYSOCK_EXPORT
	dim as zstring * INET6_ADDRSTRLEN ip
	if MySock_Host2ip(host, protocol, ip, INET6_ADDRSTRLEN) = 1 then
		return str(ip)
	else
		return str("")
	end if
end function

sub MySock_MyHost (host as zstring, host_len as uinteger) MYSOCK_EXPORT
	gethostname(@host, host_len)
end sub

function MySock_MyHostStr () as string MYSOCK_EXPORT
	dim as zstring * 256 host = ""
	gethostname(@host, 256)
	return str(host)
end function

' ---------------------------------------------------------------------------- '

end extern
