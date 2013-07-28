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
#include "internals.bi"

' ---------------------------------------------------------------------------- '

 extern "C"
 
' ---------------------------------------------------------------------------- '

'/ @brief Initiate MySock (WSAStartup)
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

'/ @brief Shutdown MySock (WSACleanup)
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

'/ @brief Convert an internat name to IP address
 '
 ' @param host [in] Internet name
 ' @param protocol [in] IP version to use (Enum protocol_e)
 '	MYSOCK_PROT_AUTO - Auto-select (will select IPv6 first if available)
 '	MYSOCK_PROT_IPV4 - Force IPv4
 '	MYSOCK_PROT_IPV6 - Force IPv6
 ' @param ip [out] Buffer that will contain the IP address
 ' @param ip_len [in] Size of the buffer (in bytes)
 '
 ' @return 1 on succes, 0 otherwise
 '/
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

'/ @brief Convert an internat name to IP address
 '
 ' @param host [in] Internet name
 ' @param protocol [in] IP version to use (Enum protocol_e)
 '	MYSOCK_PROT_AUTO - Auto-select (will select IPv6 first if available)
 '	MYSOCK_PROT_IPV4 - Force IPv4
 '	MYSOCK_PROT_IPV6 - Force IPv6
 '
 ' @return String containing the IP address on succes, empty string ("") otherwise
 '/
function MySock_Host2ipStr (host as zstring, protocol as protocol_e) as string MYSOCK_EXPORT
	dim as zstring * INET6_ADDRSTRLEN ip
	if MySock_Host2ip(host, protocol, ip, INET6_ADDRSTRLEN) = 1 then
		return str(ip)
	else
		return str("")
	end if
end function

'/ @brief Get the host name of this computer
 '
 ' @param host [out] Buffer that will contain the host name
 ' @param host_len [in] Size of the buffer (in bytes)
 '/
sub MySock_MyHost (host as zstring, host_len as uinteger) MYSOCK_EXPORT
	gethostname(@host, host_len)
end sub

'/ @brief Get the host name of this computer
 '
 ' @return String containing the host name on succes, empty string ("") otherwise
 '/
function MySock_MyHostStr () as string MYSOCK_EXPORT
	dim as zstring * 256 host = ""
	gethostname(@host, 256)
	return str(host)
end function

' ---------------------------------------------------------------------------- '

'/ @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySock_SocketGetAddr (sock as MYSOCK, ip as zstring, ip_len as uinteger, port as ushort ptr) as integer MYSOCK_EXPORT
	dim as sockaddr_storage addr
	dim as integer addr_len = sizeof(addr)
	
	if getsockname(sock, cast(sockaddr ptr, @addr), @addr_len) = 0 then
		return sockaddr2ipport(@addr, addr_len, ip, ip_len, port)
	else
		return 0
	end if
end function

'/ @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySock_SocketGetAddrStr (sock as MYSOCK, with_port as integer) as string MYSOCK_EXPORT
	dim as sockaddr_storage addr
	dim as integer addr_len = sizeof(addr)
	
	if getsockname(sock, cast(sockaddr ptr, @addr), @addr_len) = 0 then
		return sockaddr2str(@addr, addr_len, with_port)
	else
		return ""
	end if
end function

'/ @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySock_SocketGetPeerAddr (sock as MYSOCK, ip as zstring, ip_len as uinteger, port as ushort ptr) as integer MYSOCK_EXPORT
	dim as sockaddr_storage addr
	dim as integer addr_len = sizeof(addr)
	
	if getpeername(sock, cast(sockaddr ptr, @addr), @addr_len) = 0 then
		return sockaddr2ipport(@addr, addr_len, ip, ip_len, port)
	else
		return 0
	end if
end function

'/ @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySock_SocketGetPeerAddrStr (sock as MYSOCK, with_port as integer) as string MYSOCK_EXPORT
	dim as sockaddr_storage addr
	dim as integer addr_len = sizeof(addr)
	
	if getpeername(sock, cast(sockaddr ptr, @addr), @addr_len) = 0 then
		return sockaddr2str(@addr, addr_len, with_port)
	else
		return ""
	end if
end function

' ---------------------------------------------------------------------------- '

end extern
