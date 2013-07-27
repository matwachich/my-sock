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

' ---------------------------------------------------------------------------- '

function sockaddr2ipport (addr as sockaddr_storage ptr, addr_len as integer, ip as zstring, ip_len as uinteger, port as ushort ptr) as integer
	dim as zstring * INET6_ADDRSTRLEN addr_str
	dim as uinteger addr_str_len = INET6_ADDRSTRLEN
	if WSAAddressToString(cast(sockaddr ptr, addr), addr_len, NULL, addr_str, @addr_str_len) <> 0 then return 0
	
	dim as ubyte colon_pos = instrrev(addr_str, ":")
	if colon_pos = 0 then return 0
	
	'if ip <> 0 and ip_len > 0 then
		ip = left(trim(left(addr_str, colon_pos - 1), any "[]"), ip_len - 1)
	'end if
	
	if port <> NULL then 
		*port = valuint(mid(addr_str, colon_pos + 1))
	end if
	
	return 1
end function

function sockaddr2str (addr as sockaddr_storage ptr, addr_len as integer, with_port as byte) as string
	dim as zstring * INET6_ADDRSTRLEN addr_str
	dim as uinteger addr_str_len = INET6_ADDRSTRLEN
	if WSAAddressToString(cast(sockaddr ptr, addr), addr_len, NULL, addr_str, @addr_str_len) <> 0 then return str("")
	
	if with_port <> 0 then
		return str(addr_str)
	else
		return trim(left(str(addr_str), instrrev(addr_str, ":") - 1), any "[]")
	end if
end function

function af2prot (af as integer) as integer
	select case af
		case AF_UNSPEC
			return MYSOCK_PROT_AUTO
		case AF_INET
			return MYSOCK_PROT_IPV4
		case AF_INET6
			return MYSOCK_PROT_IPV6
		case else
			return MYSOCK_PROT_AUTO
	end select
end function

function prot2af (prot as integer) as integer
	select case prot
		case MYSOCK_PROT_AUTO
			return AF_UNSPEC
		case MYSOCK_PROT_IPV4
			return AF_INET
		case MYSOCK_PROT_IPV6
			return AF_INET6
		case else
			return AF_UNSPEC
	end select
end function
