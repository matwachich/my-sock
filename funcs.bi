
' uncomment the "export" before building a dll
#define MYSOCK_EXPORT export

' print debug output
#define MYSOCK_DEBUG

'#define BUFFERED
'#define MAX_PACKET_SIZE 104857600 ' 100 MB

#define DEFAULT_RECV_BUFFER_LEN 1024 ' 1 ko

' ---------------------------------------------------------------------------- '

private function sockaddr2ipport (addr as sockaddr_storage ptr, addr_len as integer, ip as zstring, ip_len as uinteger, port as ushort ptr) as integer
	dim as zstring * INET6_ADDRSTRLEN addr_str
	dim as uinteger addr_str_len = INET6_ADDRSTRLEN
	if WSAAddressToString(cast(sockaddr ptr, addr), addr_len, NULL, addr_str, @addr_str_len) <> 0 then return 0
	'print "> "; addr_str
	
	dim as ubyte colon_pos = instrrev(addr_str, ":")
	if colon_pos = 0 then return 0

	ip = left(trim(left(addr_str, colon_pos - 1), any "[]"), ip_len - 1)
	
	if port <> NULL then *port = valuint(mid(addr_str, colon_pos + 1))
	
	return 1
end function

private function af2prot (af as integer) as integer
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

private function prot2af (af as integer) as integer
	select case af
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
