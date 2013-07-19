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

#define SRV_RUNING(srv) srv->sock <> INVALID_SOCKET
#macro SRV_CLOSE_ALL(srv)
	dim as integer count = 0
	for i as integer = 0 to srv->peers_max - 1
		if PEER_CONNECTED(srv, i) then
			closesocket(srv->peers[i].sock)
			count += 1
			if count >= srv->peers_count then exit for
		end if
	next
#endmacro

#define PEER_VALID(srv, i) i >= 0 and i < srv->peers_max
#define PEER_CONNECTED(srv, i) srv->peers[i].sock <> INVALID_SOCKET
#define PEER_FREEBUFF(srv, i) if srv->peers[i].recv_buff <> NULL then deallocate(srv->peers[i].recv_buff): srv->peers[i].recv_buff = 0
#macro PEER_RESET(srv, i)
	srv->peers[i].sock = INVALID_SOCKET
	clear(srv->peers[i].addr, 0, sizeof(sockaddr_storage))
	srv->peers[i].addr_len = 0
	PEER_FREEBUFF(srv, i)
	srv->peers[i].recv_buff_len = 0
	srv->peers[i].keepalive_timeout = 0
	srv->peers[i].keepalive_interval = 0
	srv->peers[i].user_data = NULL
#endmacro
#macro PEER_SETKEEPALIVE(srv, i, timeout, interval) ' todo: voir comment faire pour que WSAIoctl ne soit pas appelé pour rien
	scope
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
		if WSAIoctl(srv->peers[i].sock, SIO_KEEPALIVE_VALS, @struct, sizeof(struct), 0, 0, @ret, 0, 0) <> 0 then
			#ifdef MYSOCK_DEBUG
			print "! WSAIoctl failed setting SIO_KEEPALIVE_VALS! (err " ; WSAGetLastError() ; ")"
			#endif
		else ' update peer's values
			srv->peers[i].keepalive_timeout = timeout
			srv->peers[i].keepalive_interval = interval
		end if
	end scope
#endmacro

' ---------------------------------------------------------------------------- '
' data structures

type _myPeer_t ' internal only
	as SOCKET sock				' socket handle
	as sockaddr_storage addr	' keep sockaddr
	as integer addr_len			' sockaddr len

	as ubyte ptr recv_buff		' receiving buffer (allocated on peer connection)
	as uinteger recv_buff_len	' size of the receiving buffer
	
	as uinteger keepalive_timeout	' keepalive
	as uinteger keepalive_interval	'

	as any ptr user_data		' user data
end type

type _mySrv_t
	as SOCKET sock
	as protocol_e protocol

	as _myPeer_t ptr peers ' peers array
	as integer peers_max
	as integer peers_count
	
	as uinteger default_recv_buff_len		' default receive buffer len -> assigned to each new peer
	as uinteger default_keepalive_timeout	' default keepalive values
	as uinteger default_keepalive_interval	'
	
	as mySrvOnConnectProc onConnect			' on peer connect callback
	as mySrvOnDisconnectProc onDisconnect	' on peer disconnect callback
	as mySrvOnRecvProc onRecv				' on data reception
	'as mySrvOnReceivingProc onReceiving
	
	as any ptr user_data	' user data
end type

' ---------------------------------------------------------------------------- '

extern "C"

' ---------------------------------------------------------------------------- '

'' @brief Create a TCP server
 '
 ' @param max_peers [in] Maximum number of simultaneous conencted peers
 ' @param protocol [in] IP version to use (Enum protocol_e)
 '	MYSOCK_PROT_AUTO - Auto-select (will select IPv6 first if available)
 '	MYSOCK_PROT_IPV4 - Force IPv4
 '	MYSOCK_PROT_IPV6 - Force IPv6
 '
 ' @return Server pointer (mySrv_t ptr) on succes, 0 otherwise
 '/
function MySrv_Create (max_peers as uinteger, protocol as protocol_e) as mySrv_t ptr MYSOCK_EXPORT
	dim as mySrv_t ptr mySrv = callocate(1, sizeof(mySrv_t))
	if mySrv = NULL then return NULL
	' ---
	mySrv->sock = INVALID_SOCKET
	mySrv->protocol = prot2af(protocol)
	' ---
	mySrv->peers = callocate(max_peers, sizeof(_myPeer_t))
	mySrv->peers_max = max_peers
	mySrv->peers_count = 0
	' ---
	mySrv->default_recv_buff_len = DEFAULT_RECV_BUFFER_LEN
	mySrv->default_keepalive_timeout = 0
	mySrv->default_keepalive_interval = 0
	' ---
	mySrv->onConnect = 0
	mySrv->onDisconnect = 0
	mySrv->onRecv = 0
	' ---
	mySrv->user_data = 0
	' ---
	if mySrv->peers = NULL then deallocate(mySrv): return NULL
	' ---
	#ifdef MYSOCK_EXPORT
	print "> Server created @" ; mySrv
	#endif
	return mySrv
end function

'' @brief Destroy a TCP server
 '
 ' This function will also call MySrv_Stop()
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return 1
 '/
function MySrv_Destroy (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
	MySrv_Stop(mySrv)
	' ---
	for i as integer = 0 to mySrv->peers_max - 1
		PEER_FREEBUFF(mySrv, i)
	next
	deallocate(mySrv->peers)
	deallocate(mySrv)
	' ---
	#ifdef MYSOCK_EXPORT
	print "> Server destroyed @" ; mySrv
	#endif
	return 1
end function

'' @brief Start a TCP server
 '
 ' This will create the listening socket
 '
 ' @param mySrv [in] Server pointer
 ' @param port [in] Port to listen
 '
 ' @return 1 on succes, 0 otherwise
 '/
function MySrv_Start (mySrv as mySrv_t ptr, port as ushort) as integer MYSOCK_EXPORT
	if SRV_RUNING(mySrv) then return 0
	' ---
	dim as addrinfo hints
	clear(hints, 0, sizeof(hints))
	dim as addrinfo ptr list

	hints.ai_family = mySrv->protocol ' maps to AF_UNSPEC, AF_INET, AF_INET6
	hints.ai_socktype = SOCK_STREAM
	hints.ai_flags = AI_PASSIVE

	if getaddrinfo(NULL, str(port), @hints, @list) <> 0 then
		#ifdef MYSOCK_DEBUG
		print "! MySrv_Start failed - (getaddrinfo failed - err" ; WSAGetLastError() ; ")"
		#endif
		return 0
	end if
	if list = 0 then
		#ifdef MYSOCK_DEBUG
		print "! MySrv_Start failed - (getaddrinfo returned empty list - err" ; WSAGetLastError() ; ")"
		#endif
		return 0
	end if

	dim as byte yes = 1
	dim as ulong yes2 = 1

	do
		mySrv->sock = socket_(list->ai_family, list->ai_socktype, list->ai_protocol)
		if mySrv->sock = INVALID_SOCKET then goto try_next
		
		if _
			setsockopt(mySrv->sock, SOL_SOCKET, SO_REUSEADDR, @yes, sizeof(yes)) = -1 or _	' reuse address
			ioctlsocket(mySrv->sock, FIONBIO, @yes2) = -1 or _	' async mode
			bind(mySrv->sock, list->ai_addr, list->ai_addrlen) = -1 or _
			listen(mySrv->sock, 10) = -1 _
		then
			goto try_next
		end if
		
		freeaddrinfo(list)
		exit do ' success
		
		try_next:
		if mySrv->sock <> INVALID_SOCKET then closesocket(mySrv->sock)
		mySrv->sock = INVALID_SOCKET
		' ---
		list = list->ai_next
		if list = NULL then
			#ifdef MYSOCK_EXPORT
			print "! MySrv_Start failed - (unable to create/bind/listen socket - err " ; WSAGetLastError() ; ")"
			#endif
			freeaddrinfo(list)
			return 0
		end if
	loop
	' ---
	mySrv->peers_count = 0
	for i as integer = 0 to mySrv->peers_max - 1
		PEER_RESET(mySrv, i)
	next
	' ---
	#ifdef MYSOCK_DEBUG
	print "> Server started @" ; mySrv ; " (Port: " ; port ; ")"
	#endif
	return 1
end function

'' @brief Stops a server, close all peers, and close listening socket
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return 1 on succes, 0 otherwise (server already stopped)
 '/
function MySrv_Stop (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
	if not SRV_RUNING(mySrv) then return 0
	' ---
	' close all peers
	SRV_CLOSE_ALL(mySrv)
	' ---
	closesocket(mySrv->sock)
	mySrv->sock = INVALID_SOCKET
	' ---
	#ifdef MYSOCK_DEBUG
	print "> Server stoped @" ; mySrv
	#endif
	return 1
end function

'' @brief Check if a server is started
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return 1 if it is started, 0 otherwise
 '/
function MySrv_IsStarted (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
	if SRV_RUNING(mySrv) then return 1
	return 0
end function

'' @brief Change the default protocol to use
 '
 ' This change only takes effect at the next MySrv_Start call
 '
 ' @param mySrv [in] Server pointer
 ' @param protocol [in] IP version to use (Enum protocol_e)
 '	MYSOCK_PROT_AUTO - Auto-select (will select IPv6 first if available)
 '	MYSOCK_PROT_IPV4 - Force IPv4
 '	MYSOCK_PROT_IPV6 - Force IPv6
 '/
sub MySrv_SetProtocol (mySrv as mySrv_t ptr, protocol as protocol_e) MYSOCK_EXPORT
	mySrv->protocol = prot2af(protocol)
end sub

'' @brief Get server's default protocol
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return MYSOCK_PROT_AUTO, MYSOCK_PROT_IPV4 or MYSOCK_PROT_IPV6
 '/
function MySrv_GetProtocol (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
	return af2prot(mySrv->protocol)
end function

'' @brief Get server's listening ip and port
 '
 ' @param mySrv [in] Server pointer
 ' @param ip [out] A C fixed-length string (ZString)
 ' @param ip_len [in] The length of ip
 ' @param port [out] Pointer to a UShort variable. Will be filled with the listened port number
 '	Can be 0 if not needed
 '
 ' @return 1 on succes, 0 otherwise
 '/
function MySrv_GetAddr (mySrv as mySrv_t ptr, ip as zstring, ip_len as uinteger, port as ushort ptr) as integer MYSOCK_EXPORT
	if not SRV_RUNING(mySrv) then return 0
	' ---
	dim as sockaddr_storage addr
	dim as integer addr_len = sizeof(addr)
	
	if getsockname(mySrv->sock, cast(sockaddr ptr, @addr), @addr_len) = 0 and _
		sockaddr2ipport(@addr, addr_len, ip, ip_len, port) = 1 then
		return 1
	else
		return 0
	end if
end function

'' @brief Get server's listening ip and port
 '
 ' @param mySrv [in] Server pointer
 ' @param port [out] Pointer to a UShort variable. Will be filled with the listened port number
 '	Can be 0 if not needed
 '
 ' @return A String containing the listened IP address (IPv4/IPv6) on succes, empty string ("") otherwise
 '/
function MySrv_GetAddrStrIp (mySrv as mySrv_t ptr, port as ushort ptr) as string MYSOCK_EXPORT
	if not SRV_RUNING(mySrv) then return str("")
	' ---
	dim as sockaddr_storage addr
	dim as integer addr_len = sizeof(addr)
	
	dim as zstring * INET6_ADDRSTRLEN ip
	
	if getsockname(mySrv->sock, cast(sockaddr ptr, @addr), @addr_len) = 0 and _
		sockaddr2ipport(@addr, addr_len, ip, INET6_ADDRSTRLEN, port) = 1 then
		return str(ip)
	else
		return str("")
	end if
end function

'' @brief Get server's listening ip and port
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return A String containing the listened ip and port ("ip:port") on succes, empty string ("") otherwise
 '/
function MySrv_GetAddrStrIpPort (mySrv as mySrv_t ptr) as string MYSOCK_EXPORT
	if not SRV_RUNING(mySrv) then return str("")
	' ---
	dim as sockaddr_storage addr
	dim as integer addr_len = sizeof(addr)
	
	dim as zstring * INET6_ADDRSTRLEN ip
	dim as ushort port
	
	if getsockname(mySrv->sock, cast(sockaddr ptr, @addr), @addr_len) = 0 and _
		sockaddr2ipport(@addr, addr_len, ip, INET6_ADDRSTRLEN, @port) = 1 then
		return str(ip) + ":" + str(port)
	else
		return str("")
	end if
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
sub MySrv_SetDefBuffLen (mySrv as mySrv_t ptr, default_buff_len as uinteger) MYSOCK_EXPORT
	mySrv->default_recv_buff_len = default_buff_len
end sub

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_GetDefBuffLen (mySrv as mySrv_t ptr) as uinteger MYSOCK_EXPORT
	return mySrv->default_recv_buff_len
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 '/
sub MySrv_SetDefKeepAlive (mySrv as mySrv_t ptr, timeout as uinteger, interval as uinteger) MYSOCK_EXPORT
	mySrv->default_keepalive_timeout = timeout
	mySrv->default_keepalive_interval = interval
end sub

'' @brief 
 '
 ' @param 
 ' @param 
 '
 '/
sub MySrv_GetDefKeepAlive (mySrv as mySrv_t ptr, timeout as uinteger ptr, interval as uinteger ptr) MYSOCK_EXPORT
	if timeout <> 0 then *timeout = mySrv->default_keepalive_timeout
	if interval <> 0 then *interval = mySrv->default_keepalive_interval
end sub

'' @brief 
 '
 ' @param 
 ' @param 
 '
 '/
sub MySrv_SetUserData (mySrv as mySrv_t ptr, user_data as any ptr) MYSOCK_EXPORT
	mySrv->user_data = user_data
end sub

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_GetUserData (mySrv as mySrv_t ptr) as any ptr MYSOCK_EXPORT
	return mySrv->user_data
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
sub MySrv_SetCallbacks (mySrv as mySrv_t ptr, _
						onConnect as mySrvOnConnectProc, _
						onDisconnect as mySrvOnDisconnectProc, _
						onRecv as mySrvOnRecvProc) MYSOCK_EXPORT ', onReceiving as mySrvOnReceivingProc)
	mySrv->onConnect = onConnect
	mySrv->onDisconnect = onDisconnect
	mySrv->onRecv = onRecv
	'mySrv->onReceiving = onReceiving
end sub

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
sub MySrv_Process (mySrv as mySrv_t ptr) MYSOCK_EXPORT
	if mySrv->sock <> INVALID_SOCKET then
		dim as sockaddr_storage new_addr
		dim as integer new_addr_len = sizeof(new_addr)
		
		dim as SOCKET new_sock = accept(mySrv->sock, cast(sockaddr ptr, @new_addr), @new_addr_len)
		' New peer connected!
		if new_sock <> INVALID_SOCKET then
			' search free peer slot to store the new connection
			dim as integer free_slot = -1
			for i as integer = 0 to mySrv->peers_max - 1
				if not PEER_CONNECTED(mySrv, i) then free_slot = i: exit for
			next
			' check if there is a free peer slot
			if free_slot <> -1 then
				' store new peer
				dim as ulong yes = 1
				ioctlsocket(new_sock, FIONBIO, @yes)
				' ---
				' init new peer
				mySrv->peers[free_slot].sock = new_sock
				mySrv->peers[free_slot].addr = new_addr
				mySrv->peers[free_slot].addr_len = new_addr_len
				mySrv->peers[free_slot].recv_buff = allocate(mySrv->default_recv_buff_len)
				mySrv->peers[free_slot].recv_buff_len = mySrv->default_recv_buff_len
				mySrv->peers[free_slot].user_data = NULL
				' ---
				PEER_SETKEEPALIVE(mySrv, free_slot, mySrv->default_keepalive_timeout, mySrv->default_keepalive_interval)
				' ---
				mySrv->peers_count += 1
				' onConnect callback
				if mySrv->onConnect <> NULL then mySrv->onConnect(mySrv, free_slot)
			else
				' sorry new_sock, server is full! :p
				closesocket(new_sock)
			end if
		end if
	end if
	' ---
	' ---
	dim as integer ret = 0, disconnect = 0
	for i as integer = 0 to mySrv->peers_max - 1
		if not PEER_CONNECTED(mySrv, i) then continue for
		disconnect = 0
		' ---
		#ifdef BUFFERED
		
		#else
		ret = recv(mySrv->peers[i].sock, mySrv->peers[i].recv_buff, mySrv->peers[i].recv_buff_len, 0)
		select case ret
			case is > 0 ' data received
				if mySrv->onRecv <> NULL then
					mySrv->onRecv(mySrv, i, mySrv->peers[i].recv_buff, ret)
				end if
				clear(*(mySrv->peers[i].recv_buff), 0, mySrv->peers[i].recv_buff_len)
			case 0 ' disconnected
				disconnect = 1
			case -1
				if WSAGetLastError() <> WSAEWOULDBLOCK then ' error => disconnect
					disconnect = 1
				end if
		end select
		' ---
		if disconnect then
			closesocket(mySrv->peers[i].sock) ' just to be sure
			if mySrv->onDisconnect <> NULL then
				mySrv->onDisconnect(mySrv, i)
			end if
			PEER_RESET(mySrv, i)
			mySrv->peers_count -= 1
		end if
		#endif
	next
end sub

' ---------------------------------------------------------------------------- '

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_PeerSend (mySrv as mySrv_t ptr, peer_id as integer, data_ as byte ptr, data_len as uinteger) as integer MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) then return -1
	if not PEER_CONNECTED(mySrv, peer_id) then return 0
	
	#ifdef BUFFERED ' send first packet with data_ len
	if send(mySrv->peers[peer_id].sock, cast(byte ptr, @data_len), sizeof(data_len), 0) <> sizeof(data_len) then return -1
	#endif
	
	dim as integer total = 0, remain = data_len, n = 0

	do while total < data_len
		n = send(mySrv->peers[peer_id].sock, @data_[total], remain, 0)
		if n = -1 and WSAGetLastError() <> WSAEWOULDBLOCK then return -1
		total += n
		remain -= n
	loop

	return total
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_Broadcast (mySrv as mySrv_t ptr, data_ as byte ptr, data_len as uinteger) as integer MYSOCK_EXPORT
	if mySrv->peers_count = 0 then return 0
	
	dim as integer count = 0

	for i as integer = 0 to mySrv->peers_max - 1
		if PEER_CONNECTED(mySrv, i) then
			if MySrv_PeerSend(mySrv, i, data_, data_len) <> -1 then count += 1
			if count >= mySrv->peers_count then
				exit for
			end if
		end if
	next

	return count
end function

'' @brief Close peer connection
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 '
 ' @return 
 '/
function MySrv_Close (mySrv as mySrv_t ptr, peer_id as integer) as integer MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) then return -1
	if not PEER_CONNECTED(mySrv, peer_id) then return 0
	' ---
	return closesocket(mySrv->peers[peer_id].sock)
end function

'' @brief Close all peers connections
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return 
 '/
function MySrv_CloseAll (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
	SRV_CLOSE_ALL(mySrv)
	return count ' declared in SRV_CLOSE_ALL() macro
end function

'' @brief Get connected peers count
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return 
 '/
function MySrv_PeersCount (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
	return mySrv->peers_count
end function

'' @brief Fill an array with all connected peers IDs
 '
 ' @param mySrv [in] Server pointer
 ' @param peers_ids() [out] C-Array that will be filled with peers IDs
 '
 ' @return 
 '/
function MySrv_PeersGetAll (mySrv as mySrv_t ptr, peer_ids as integer ptr, peers_ids_size as integer) as integer MYSOCK_EXPORT
	if mySrv->peers_count = 0 then return 0
	
	dim as integer cursor = 0
	for i as integer = 0 to mySrv->peers_max - 1
		if PEER_CONNECTED(mySrv, i) then
			peer_ids[cursor] = i
			cursor += 1
			' ---
			if cursor >= peers_ids_size or cursor >= mySrv->peers_count then exit for
		end if
	next
	
	return cursor
end function

' call mySrvIterateProc for every connected peer
function MySrv_PeersIterate (mySrv as mySrv_t ptr, callback as mySrvIterateProc, user_data as any ptr) as integer MYSOCK_EXPORT
	if mySrv->peers_count = 0 then return 0
	
	dim as integer count = 0
	for i as integer = 0 to mySrv->peers_max - 1
		if PEER_CONNECTED(mySrv, i) then
			count += 1
			if callback(mysrv, i, user_data) = 0 then exit for
			' ---
			if count >= mySrv->peers_count then exit for
		end if
	next
	
	return count
end function

' get peer's address in form ipv4:port | [ipv6]:port
function MySrv_PeerGetAddr (mySrv as mySrv_t ptr, peer_id as integer, ip as zstring, ip_len as integer, port as ushort ptr) as integer MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return 0
	
	if sockaddr2ipport(@(mySrv->peers[peer_id].addr), mySrv->peers[peer_id].addr_len, ip, ip_len, port) = 1 then return 1
	return 0
	
	'dim as sockaddr_storage addr
	'dim as integer addr_len = sizeof(sockaddr_storage)
	
	'if getpeername(mySrv->peers[peer_id].sock, cast(sockaddr ptr, @addr), @addr_len) = 0 and _
	'	sockaddr2ipport(@addr, addr_len, ip, ip_len, port) = 1 then
	'	return 1
	'else
	'	return 0
	'end if
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_PeerGetAddrStrIp (mySrv as mySrv_t ptr, peer_id as integer, port as ushort ptr) as string MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return str("")
	' ---
	dim as zstring * INET6_ADDRSTRLEN ip
	
	if sockaddr2ipport(@(mySrv->peers[peer_id].addr), mySrv->peers[peer_id].addr_len, ip, INET6_ADDRSTRLEN, port) = 1 then
		return str(ip)
	else
		return str("")
	end if
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_PeerGetAddrStrIpPort (mySrv as mySrv_t ptr, peer_id as integer) as string MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return str("")
	' ---
	dim as zstring * INET6_ADDRSTRLEN ip
	dim as ushort port
	
	if sockaddr2ipport(@(mySrv->peers[peer_id].addr), mySrv->peers[peer_id].addr_len, ip, INET6_ADDRSTRLEN, @port) = 1 then
		return str(ip) + ":" + str(port)
	else
		return str("")
	end if
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_PeerSetBuffLen (mySrv as mySrv_t ptr, peer_id as integer, buff_len as uinteger) as integer MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return 0
	
	mySrv->peers[peer_id].recv_buff = reallocate(mySrv->peers[peer_id].recv_buff, buff_len)
	if mySrv->peers[peer_id].recv_buff = NULL then return 0
	
	mySrv->peers[peer_id].recv_buff_len = buff_len
	return 1
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_PeerGetBuffLen (mySrv as mySrv_t ptr, peer_id as integer) as uinteger MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return 0
	
	return mySrv->peers[peer_id].recv_buff_len
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 '/
sub MySrv_PeerSetKeepAlive (mySrv as mySrv_t ptr, peer_id as integer, timeout as uinteger, interval as uinteger) MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return
	
	PEER_SETKEEPALIVE(mySrv, peer_id, timeout, interval)
end sub

'' @brief 
 '
 ' @param 
 ' @param 
 '
 '/
sub MySrv_PeerGetKeepAlive (mySrv as mySrv_t ptr, peer_id as integer, timeout as uinteger ptr, interval as uinteger ptr) MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return
	
	if timeout <> 0 then *timeout = mySrv->peers[peer_id].keepalive_timeout
	if interval <> 0 then *interval = mySrv->peers[peer_id].keepalive_interval
end sub

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_PeerSetUserData (mySrv as mySrv_t ptr, peer_id as integer, user_data as any ptr) as integer MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return 0
	
	mySrv->peers[peer_id].user_data = user_data
	return 1
end function

'' @brief 
 '
 ' @param 
 ' @param 
 '
 ' @return 
 '/
function MySrv_PeerGetUserData (mySrv as mySrv_t ptr, peer_id as integer) as any ptr MYSOCK_EXPORT
	if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return 0
	
	return mySrv->peers[peer_id].user_data
end function

' ---------------------------------------------------------------------------- '

end extern
