#ifdef __FB_WIN32__
    '#define UNICODE
    '#define WIN32_LEAN_AND_MEAN
    '#include "windows.bi"
    #include "win\ws2tcpip.bi"
    #include "win\mswsock.bi"
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
#error MySock is designed for Windows only!
#endif

#include "mysock.bi"
#include "internals.bi"

' ---------------------------------------------------------------------------- '
' internal macros

#define SRV_RUNING(srv) srv->sock <> INVALID_SOCKET
#macro SRV_CLOSE_ALL(srv)
    dim as integer count = 0
    for i as integer = 0 to srv->peers_max - 1
        if PEER_CONNECTED(srv, i) then
            shutdown(srv->peers[i].sock, 1)
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
    srv->peers[i].recv_buff_ofset = 0
    srv->peers[i].is_receiving = 0
    srv->peers[i].recv_timer = 0
    srv->peers[i].recv_timeout = 0
    srv->peers[i].keepalive_timeout = 0
    srv->peers[i].keepalive_interval = 0
    srv->peers[i].user_data = NULL
#endmacro
#macro PEER_SETKEEPALIVE(srv, i, timeout, interval) ' todo: voir comment faire pour que WSAIoctl ne soit pas appel� pour rien
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
    as sockaddr_storage addr	' must keep this, so that event if peer.sock is invalid, we
    as uinteger addr_len		' still can get the address the peer connected from (usefull for disconnect callback)

    as ubyte ptr recv_buff		' receiving buffer (allocated on peer connection)
    as MYSIZE recv_buff_len	    ' size of the receiving buffer
    as MYSIZE recv_buff_ofset   ' current offset in the receive buffer (position of the first free byte)
    'as MYSIZE packet_len
    'as MYSIZE total_recv
    as byte is_receiving		' set to 0 when waiting for a packet size, otherwise if waiting data
    
    as double recv_timer
    as uinteger recv_timeout
    
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
    
    as uinteger default_recv_timeout
    
    as uinteger default_keepalive_timeout	' default keepalive values
    as uinteger default_keepalive_interval	'
    
    as mySrvOnConnectProc onConnect			' on peer connect callback
    as mySrvOnDisconnectProc onDisconnect	' on peer disconnect callback
    as mySrvOnPacketRecvProc onPacketRecv				' on packet received
    as mySrvOnReceivingProc onReceiving		' on packet receiving
    as mySrvOnTimeOutProc onTimeOut 		' on packet reception timeout
    
    as mySockPacketPrepareProc packetPrepare
    
    as any ptr user_data	' user data
end type

' ---------------------------------------------------------------------------- '

extern "C"

' ---------------------------------------------------------------------------- '

'/ @brief Create a TCP server
 '
 ' @param max_peers [in] Maximum number of simultaneous conencted peers
 '	Valid peers ids will be >= 0 and < max_peers
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
    mySrv->default_recv_timeout = MYSOCK_DEF_RECV_TIMEOUT
    ' ---
    mySrv->default_keepalive_timeout = 0
    mySrv->default_keepalive_interval = 0
    ' ---
    mySrv->onConnect = 0
    mySrv->onDisconnect = 0
    mySrv->onPacketRecv = 0
    mySrv->onReceiving = 0
    mySrv->onTimeOut = 0
    ' ---
    mySrv->packetPrepare = 0
    ' ---
    mySrv->user_data = 0
    ' ---
    if mySrv->peers = NULL then deallocate(mySrv): return NULL
    ' ---
    #ifdef MYSOCK_DEBUG
    print "> Server created @" ; mySrv
    #endif
    return mySrv
end function

'/ @brief Destroy a TCP server
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
    #ifdef MYSOCK_DEBUG
    print "> Server destroyed @" ; mySrv
    #endif
    return 1
end function

'/ @brief Start a TCP server
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
    dim as addrinfo ptr list, to_free

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
    
    to_free = list

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
        
        freeaddrinfo(to_free)
        exit do ' success
        
        try_next:
        if mySrv->sock <> INVALID_SOCKET then closesocket(mySrv->sock)
        mySrv->sock = INVALID_SOCKET
        ' ---
        list = list->ai_next
        if list = NULL then
            #ifdef MYSOCK_DEBUG
            print "! MySrv_Start failed - (unable to create/bind/listen socket - err " ; WSAGetLastError() ; ")"
            #endif
            freeaddrinfo(to_free)
            return 0
        end if
    loop
    ' ---
    mySrv->peers_count = 0
    for i as integer = 0 to mySrv->peers_max - 1
        mySrv->peers[i].sock = INVALID_SOCKET
        'PEER_RESET(mySrv, i) ' No need to reset the entire peer structure, this will be done when a peer connects
    next
    ' ---
    #ifdef MYSOCK_DEBUG
    print "> Server started @" ; mySrv ; " (Port: " ; port ; ")"
    #endif
    return 1
end function

'/ @brief Stops a server, close all peers, and close listening socket
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
    shutdown(mySrv->sock, 1)
    MySrv_Process(mySrv) ' to call disconnect callback
    ' ---
    closesocket(mySrv->sock)
    mySrv->sock = INVALID_SOCKET
    ' ---
    #ifdef MYSOCK_DEBUG
    print "> Server stoped @" ; mySrv
    #endif
    return 1
end function

'/ @brief Check if a server is started
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return 1 if it is started, 0 otherwise
 '/
function MySrv_IsStarted (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
    if SRV_RUNING(mySrv) then return 1
    return 0
end function

'/ @brief Change the default protocol to use
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

'/ @brief Get server's default protocol
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return MYSOCK_PROT_AUTO, MYSOCK_PROT_IPV4 or MYSOCK_PROT_IPV6
 '/
function MySrv_GetProtocol (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
    return af2prot(mySrv->protocol)
end function

'/ @brief Get server's listening ip and port
 '
 ' @param mySrv [in] Server pointer
 ' @param ip [out] Buffer that will contain the server's ip
 ' @param ip_len [in] Size of the buffer (in bytes)
 ' @param port [out] Pointer to a UShort variable. Will be filled with the listened port number
 '	Can be 0 if not needed
 '
 ' @return 1 on succes, 0 otherwise
 '/
function MySrv_GetAddr (mySrv as mySrv_t ptr, ip as zstring, ip_len as MYSIZE, port as ushort ptr) as integer MYSOCK_EXPORT
    if not SRV_RUNING(mySrv) then return 0
    ' ---
    dim as sockaddr_storage addr
    dim as integer addr_len = sizeof(addr)
    
    if getsockname(mySrv->sock, cast(sockaddr ptr, @addr), @addr_len) = 0 then
        return sockaddr2ipport(@addr, addr_len, ip, ip_len, port)
    else
        return 0
    end if
end function

'/ @brief Get server's listening ip and port
 '
 ' @param mySrv [in] Server pointer
 ' @param port [in] Set to non 0 to append port number to the end of the address
 '
 ' @return A String containing the listened IP address (IPv4/IPv6) on succes, empty string ("") otherwise
 '/
function MySrv_GetAddrStr (mySrv as mySrv_t ptr, with_port as integer) as string MYSOCK_EXPORT
    if not SRV_RUNING(mySrv) then return str("")
    ' ---
    dim as sockaddr_storage addr
    dim as integer addr_len = sizeof(addr)
    
    if getsockname(mySrv->sock, cast(sockaddr ptr, @addr), @addr_len) = 0 then
        return sockaddr2str(cast(sockaddr_storage ptr, @addr), addr_len, with_port)
    else
        return str("")
    end if
end function

'/ @brief Set TCP Server's default receive timeout
 '
 ' When a packet size or packet data is being received, and no data has been received
 ' for `timeout` seconds, then the client is disconnected and the myClnOnTimeOutProc is
 ' called with the partial received data
 '
 ' This will be assigned to each new connecting peer.
 '
 ' @param mySrv [in] Server pointer
 ' @param timeout [in] Default receive timeout (in seconds)
 '/
sub MySrv_SetDefRecvTimeOut (mySrv as mySrv_t ptr, timeout as uinteger)
    mySrv->default_recv_timeout = timeout
end sub

'/ @brief Get TCP Server's default receive timeout
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return Default receive timeout (in seconds)
 '/
function MySrv_GetDefRecvTimeOut (mySrv as mySrv_t ptr) as uinteger
    return mySrv->default_recv_timeout
end function

'/ @brief Set keepalive status and times
 '
 ' @param mySrv [in] Server pointer
 ' @param timeout [in] Keep alive timeout (in seconds)
 ' @param interval [in] Keep alive probes interval (in seconds)
 '
 '	If 'timeout' and 'interval' = 0 then the keepalive packets sending is deactivated.
 '	Otherwise, 'timeout' is the time with no activity until the first keep-alive packet is sent,
 '	and 'interval' is the delay between successive keep-alive packets
 '
 '	This function uses WSAIoctl & SIO_KEEPALIVE_VALS
 '/
sub MySrv_SetDefKeepAlive (mySrv as mySrv_t ptr, timeout as uinteger, interval as uinteger) MYSOCK_EXPORT
    mySrv->default_keepalive_timeout = timeout
    mySrv->default_keepalive_interval = interval
end sub

'/ @brief Get keepalive status and times
 '
 ' @param mySrv [in] Server pointer
 ' @param timeout [out] Will contain keepalive timeout (in seconds)
 ' @param interval [out] Will contain keepalive interval (in seconds)
 '/
sub MySrv_GetDefKeepAlive (mySrv as mySrv_t ptr, timeout as uinteger ptr, interval as uinteger ptr) MYSOCK_EXPORT
    if timeout <> 0 then *timeout = mySrv->default_keepalive_timeout
    if interval <> 0 then *interval = mySrv->default_keepalive_interval
end sub

'/ @brief Get server's listening socket identifier
 '
 ' If the server is not started, then this function will return -1 (INVALID_SOCKET)
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return Socket ID
 '/
function MySrv_GetSocket (mySrv as mySrv_t ptr) as integer
    return mySrv->sock
end function

'/ @brief Set user data attached to a server
 '
 ' @param mySrv [in] Server pointer
 ' @param user_data [in] User data
 '/
sub MySrv_SetUserData (mySrv as mySrv_t ptr, user_data as any ptr) MYSOCK_EXPORT
    mySrv->user_data = user_data
end sub

'/ @brief Get user data attached to a server
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return User data
 '/
function MySrv_GetUserData (mySrv as mySrv_t ptr) as any ptr MYSOCK_EXPORT
    return mySrv->user_data
end function

'/ @brief Set one callback function for a Server
 '
 ' @param mySrv [in] Server pointer
 ' @param callback [in] Which callback to set
 '  MYSOCK_CB_CONNECT       Set the onConnect callback (mySrvOnConnectProc)
 '  MYSOCK_CB_DISCONNECT    Set the onDisconnect callback (mySrvOnDisconnectProc)
 '  MYSOCK_CB_PACKETRECV    Set the onPacketRecv callback (mySrvOnPacketRecvProc)
 '  MYSOCK_CB_RECEIVING     Set the onReceiving callback (mySrvOnReceivingProc)
 '  MYSOCK_CB_TIMEOUT       Set the onTimeOut callback (mySrvOnTimeOutProc)
 '  MYSOCK_CB_PACKET_PREPARE  Set the packet preparation callback (mySockPacketPrepareProc)
 ' @param proc [in] Callback function pointer
 '/
sub MySrv_SetCallback (mySrv as mySrv_t ptr, callback as callback_e, proc as any ptr)
    select case callback
        case MYSOCK_CB_CONNECT
            mySrv->onConnect = proc
        case MYSOCK_CB_DISCONNECT
            mySrv->onDisconnect = proc
        case MYSOCK_CB_PACKETRECV
            mySrv->onPacketRecv = proc
        case MYSOCK_CB_RECEIVING
            mySrv->onReceiving = proc
        case MYSOCK_CB_TIMEOUT 
            mySrv->onTimeOut = proc
        case MYSOCK_CB_PACKET_PREPARE
            mySrv->packetPrepare = proc
    end select
end sub

'/ @brief Set callback functions for a server
 '
 ' @param mySrv [in] Server pointer
 ' @param onConnect [in] Pointer to a mySrvOnConnectProc
 '	sub (mySrv as mySrv_t ptr, peer_id as integer)
 ' @param onDisconnect [in] Pointer to a mySrvOnDisconnectProc
 '	sub (mySrv as mySrv_t ptr, peer_id as integer, partial_data as ubyte ptr, data_len as MYSIZE, excepted_len as MYSIZE)
 ' @param onPacketRecv [in] Pointer to a mySrvOnPacketRecvProc
 '	sub (mySrv as mySrv_t ptr, peer_id as integer, data_ as ubyte ptr, data_len as MYSIZE)
 ' @param onReceiving [in] Pointer to a mySrvOnReceivingProc
 '	sub (mySrv as mySrv_t ptr, peer_id as integer, received_bytes as MYSIZE, total_bytes as MYSIZE)
 ' @param onTimeOut [in] Pointer to a mySrvOnTimeOutProc
 '  sub (mySrv as mySrv_t ptr, peer_id as integer, partial_data as ubyte ptr, data_len as MYSIZE, excepted_len as MYSIZE)
 '/
sub MySrv_SetCallbacks (mySrv as mySrv_t ptr, _
                        onConnect as mySrvOnConnectProc, _
                        onDisconnect as mySrvOnDisconnectProc, _
                        onPacketRecv as mySrvOnPacketRecvProc, _
                        onReceiving as mySrvOnReceivingProc, _
                        onTimeOut as mySrvOnTimeOutProc) MYSOCK_EXPORT
    mySrv->onConnect = onConnect
    mySrv->onDisconnect = onDisconnect
    mySrv->onPacketRecv = onPacketRecv
    mySrv->onReceiving = onReceiving
    mySrv->onTimeOut = onTimeOut
end sub

'/ @brief Process a server. Accept new peers, receive data and call callbacks
 '
 '	This function must be called in loop. You should also call this function once
 '	after destroying a server in order to call the disconnect callback.
 '
 ' @param mySrv [in] Server pointer
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
                mysrv->peers[free_slot].addr = new_addr ' store it (rather than call getpeername) to be able to retreive
                mySrv->peers[free_slot].addr_len = new_addr_len ' peer's address when it's disconnected (in the onDisconnect callback)
                mySrv->peers[free_slot].recv_buff = callocate(1, sizeof(ulong))
                mySrv->peers[free_slot].recv_buff_len = sizeof(ulong)
                mySrv->peers[free_slot].recv_buff_ofset = 0
                mySrv->peers[free_slot].is_receiving = 0
                mySrv->peers[free_slot].recv_timer = 0
                mySrv->peers[free_slot].recv_timeout = mySrv->default_recv_timeout
                mySrv->peers[free_slot].user_data = NULL
                ' ---
                PEER_SETKEEPALIVE(mySrv, free_slot, mySrv->default_keepalive_timeout, mySrv->default_keepalive_interval)
                ' ---
                mySrv->peers_count += 1
                ' onConnect callback
                if mySrv->onConnect <> NULL then mySrv->onConnect(mySrv, free_slot)
            else
                ' sorry new_sock, server is full! :p
                shutdown(new_sock, 2)
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
        ret = recv( _
            mySrv->peers[i].sock, _
            mySrv->peers[i].recv_buff + mySrv->peers[i].recv_buff_ofset, _		' receive at first free byte
            mySrv->peers[i].recv_buff_len - mySrv->peers[i].recv_buff_ofset, _	' max = size - offset
            0)
        ' ---
        select case ret
            case is > 0 ' data received
                mySrv->peers[i].recv_buff_ofset += ret
                ' re-init recv timer
                mySrv->peers[i].recv_timer = timer()
                ' ---
                if mySrv->peers[i].is_receiving = 0 then ' received packet size
                    if mySrv->peers[i].recv_buff_ofset = sizeof(ulong) then ' complete packet size
                        dim as ulong packet_size = *cast(ulong ptr, mySrv->peers[i].recv_buff)
                        packet_size = ntohl(packet_size)
                        ' ---
                        mySrv->peers[i].recv_buff = reallocate(mySrv->peers[i].recv_buff, packet_size)
                        mySrv->peers[i].recv_buff_len = packet_size ' ***
                        mySrv->peers[i].recv_buff_ofset = 0
                        mySrv->peers[i].is_receiving = 1
                        ' ---
                        if mySrv->onReceiving <> 0 then
                            mySrv->onReceiving(mySrv, i, 0, packet_size)
                        end if
                    end if
                else
                    if mySrv->onReceiving <> 0 then
                        mySrv->onReceiving(mySrv, i, mySrv->peers[i].recv_buff_ofset, mySrv->peers[i].recv_buff_len)
                    end if
                    ' ---
                    if mySrv->peers[i].recv_buff_ofset = mySrv->peers[i].recv_buff_len then ' packet complete ' ***
                        if mySrv->onPacketRecv <> NULL then
                            if mySrv->packetPrepare <> 0 then
                                mySrv->packetPrepare(mySrv->peers[i].recv_buff, mySrv->peers[i].recv_buff_len, MYSOCK_PACKET_RECV)
                            end if
                            ' ---
                            mySrv->onPacketRecv(mySrv, i, mySrv->peers[i].recv_buff, mySrv->peers[i].recv_buff_len)
                        end if
                        ' ---
                        ' reset peer to pakce-size-wait state
                        mySrv->peers[i].recv_buff = reallocate(mySrv->peers[i].recv_buff, sizeof(ulong))
                        mySrv->peers[i].recv_buff_len = sizeof(ulong)
                        mySrv->peers[i].recv_buff_ofset = 0
                        mySrv->peers[i].is_receiving = 0
                    end if
                end if
            case 0 ' disconnected
                disconnect = 1
            case -1
                if WSAGetLastError() <> WSAEWOULDBLOCK then ' error => disconnect
                    disconnect = 1
                end if
        end select
        ' ---
        ' Receive timeout check
        if mySrv->peers[i].recv_buff_ofset > 0 and _
            timer() - mySrv->peers[i].recv_timer > mySrv->peers[i].recv_timeout then
            ' ---
            if mySrv->onTimeOut <> 0 then
                mySrv->onTimeOut(mySrv, i, mySrv->peers[i].recv_buff, mySrv->peers[i].recv_buff_ofset, mySrv->peers[i].recv_buff_len)
                mySrv->peers[i].is_receiving = 0
            end if
            ' ---
            disconnect = 1
        end if
        ' ---
        if disconnect then
            if mySrv->onDisconnect <> NULL then
                if mySrv->peers[i].is_receiving then
                    mySrv->onDisconnect(mySrv, i, mySrv->peers[i].recv_buff, mySrv->peers[i].recv_buff_ofset, mySrv->peers[i].recv_buff_len)
                else
                    mySrv->onDisconnect(mySrv, i, 0, 0, 0)
                end if
            end if
            ' ---
            closesocket(mySrv->peers[i].sock)
            mySrv->peers[i].sock = INVALID_SOCKET
            ' ---
            if mySrv->peers[i].recv_buff <> 0 then deallocate(mySrv->peers[i].recv_buff): mySrv->peers[i].recv_buff = 0
            ' ---
            mySrv->peers_count -= 1
        end if
    next
end sub

' ---------------------------------------------------------------------------- '

'/ @brief Send data to a connected peer
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 ' @param data_ [in] Pointer to a buffer that contains the data
 ' @param data_len [in] Size of the buffer (in bytes)
 '
 ' @return total bytes sent, or 0 if the peer is not connected, or -1 if peer_id is invalid
 '/
function MySrv_PeerSend (mySrv as mySrv_t ptr, peer_id as integer, data_ as ubyte ptr, data_len as MYSIZE) as integer MYSOCK_EXPORT
    if not PEER_VALID(mySrv, peer_id) then return -1
    if not PEER_CONNECTED(mySrv, peer_id) then return 0
    
    ' send packet size
    dim as MYSIZE net_data_len = htonl(data_len)
    if send(mySrv->peers[peer_id].sock, cast(ubyte ptr, @net_data_len), sizeof(ulong), 0) <> sizeof(ulong) then return -1
    
    ' prepare packet
    if mySrv->packetPrepare <> 0 then
        mySrv->packetPrepare(data_, data_len, MYSOCK_PACKET_SEND)
    end if
    
    dim as integer total = 0, remain = data_len, n = 0

    do while total < data_len
        n = send(mySrv->peers[peer_id].sock, @data_[total], remain, 0)
        if n = -1 and WSAGetLastError() <> WSAEWOULDBLOCK then return -1
        total += n
        remain -= n
    loop

    return total
end function

'/ @brief Send data to all connected peers
 '
 ' @param mySrv [in] Server pointer
 ' @param data_ [in] Pointer to a buffer that contains the data
 ' @param data_len [in] Size of the buffer (in bytes)
 '
 ' @return Total peers that data has been sent to
 '/
function MySrv_Broadcast (mySrv as mySrv_t ptr, data_ as ubyte ptr, data_len as MYSIZE) as integer MYSOCK_EXPORT
    if mySrv->peers_count = 0 then return 0
    
    dim as integer count = 0

    for i as integer = 0 to mySrv->peers_max - 1
        if PEER_CONNECTED(mySrv, i) then
            if MySrv_PeerSend(mySrv, i, data_, data_len) > 0 then count += 1
            if count >= mySrv->peers_count then
                exit for
            end if
        end if
    next

    return count
end function

'/ @brief Close peer connection
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 '
 ' @return 1 if succes, 0 if error or peer_id is not connected, -1 if peer_id is invalid
 '/
function MySrv_Close (mySrv as mySrv_t ptr, peer_id as integer) as integer MYSOCK_EXPORT
    if not PEER_VALID(mySrv, peer_id) then return -1
    if not PEER_CONNECTED(mySrv, peer_id) then return 0
    ' ---
    if shutdown(mySrv->peers[peer_id].sock, 1) = 0 then return 1
    return 0
end function

'/ @brief Close all peers connections
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return Total closed connections
 '/
function MySrv_CloseAll (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
    SRV_CLOSE_ALL(mySrv)
    return count ' declared in SRV_CLOSE_ALL() macro
end function

'/ @brief Get connected peers count
 '
 ' @param mySrv [in] Server pointer
 '
 ' @return Connected peers count
 '/
function MySrv_PeersCount (mySrv as mySrv_t ptr) as integer MYSOCK_EXPORT
    return mySrv->peers_count
end function

'/ @brief Fill an array with all connected peers IDs
 '
 ' @param mySrv [in] Server pointer
 ' @param peers_ids [out] Pointer to a buffer/array of integers that will be filled with peers' ids
 ' @param peers_ids_size [in] Size of the array (in elements of sizeof(integer))
 '
 ' @return Number of elements filled
 '/
function MySrv_PeersGetAll (mySrv as mySrv_t ptr, peer_ids as integer ptr, peers_ids_size as MYSIZE) as integer MYSOCK_EXPORT
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

'/ @brief Call mySrvIterateProc for every connected peer
 '
 ' @param mySrv [in] Server pointer
 ' @param callback [in] Pointer to a mySrvIterateProc function
 '	function (mySrv as mySrv_t ptr, peer_id as integer, user_data as any ptr) as integer
 '	if the callback returns 0, then the iteration stops
 ' @param user_data [in] User data passed to the callback function
 '
 ' @return Number of times the callback has been called
 '/
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

'/ @brief Get peer's IP and Port (C-style)
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 ' @param ip [out] Buffer that will be filled with peer's IP
 ' @param ip_len [in] Size of the buffer
 ' @param port [out] Pointer to a UShort variable that will contain peer's port number
 '
 ' @return 1 on succes, 0 otherwise
 '/
function MySrv_PeerGetAddr (mySrv as mySrv_t ptr, peer_id as integer, ip as zstring, ip_len as MYSIZE, port as ushort ptr) as integer MYSOCK_EXPORT
    if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return 0
    
    return sockaddr2ipport(@(mySrv->peers[peer_id].addr), mySrv->peers[peer_id].addr_len, ip, ip_len, port)
end function

'/ @brief Get peer's IP and Port (FB String)
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 ' @param with_port [in] Set to non 0 to append the port number to the end of the String
 '
 ' @return String with IP:Port on succes, empty string ("") otherwise
 '/
function MySrv_PeerGetAddrStr (mySrv as mySrv_t ptr, peer_id as integer, with_port as integer) as string MYSOCK_EXPORT
    if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return str("")
    
    return sockaddr2str(@(mySrv->peers[peer_id].addr), mySrv->peers[peer_id].addr_len, with_port)
end function

'/ @brief Set peer's receive timeout
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 ' @param timeout [in] Receive timeout (in seconds)
 '/
sub MySrv_PeerSetRecvTimeOut (mySrv as mySrv_t ptr, peer_id as integer, timeout as uinteger)
    if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return
    
    mySrv->peers[peer_id].recv_timeout = timeout
end sub

'/ @brief Get peer's receive timeout
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 '
 ' @return Receive timeout (in seconds)
 '/
function MySrv_PeerGetRecvTimeOut (mySrv as mySrv_t ptr, peer_id as integer) as uinteger
    if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return 0
    
    return mySrv->peers[peer_id].recv_timeout
end function

'/ @brief Set peer's keepalive status/values
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 ' @param timeout [in] Keep alive timeout (in seconds)
 ' @param interval [in] Keep alive probes interval (in seconds)
 '
 '	If 'timeout' and 'interval' = 0 then the keepalive packets sending is deactivated.
 '	Otherwise, 'timeout' is the time with no activity until the first keep-alive packet is sent,
 '	and 'interval' is the delay between successive keep-alive packets
 '
 '	This function uses WSAIoctl & SIO_KEEPALIVE_VALS
 '/
sub MySrv_PeerSetKeepAlive (mySrv as mySrv_t ptr, peer_id as integer, timeout as uinteger, interval as uinteger) MYSOCK_EXPORT
    if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return
    
    PEER_SETKEEPALIVE(mySrv, peer_id, timeout, interval)
end sub

'/ @brief Get peer's keepalive status/values
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 ' @param timeout [out] Will contain Keep alive timeout (in seconds)
 ' @param interval [out] Will contain Keep alive interval (in seconds)
 '/
sub MySrv_PeerGetKeepAlive (mySrv as mySrv_t ptr, peer_id as integer, timeout as uinteger ptr, interval as uinteger ptr) MYSOCK_EXPORT
    if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return
    
    if timeout <> 0 then *timeout = mySrv->peers[peer_id].keepalive_timeout
    if interval <> 0 then *interval = mySrv->peers[peer_id].keepalive_interval
end sub

'/ @brief Get peer's socket identifier
 '
 ' If peer_id is not a valid ID or peer_id is not a connected peer, then -1
 '	is returned (INVALID_SOCKET)
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 '
 ' @return Socket ID
 '/
function MySrv_PeerGetSocket (mySrv as mySrv_t ptr, peer_id as integer) as integer
    if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return -1
    
    return mySrv->peers[peer_id].sock
end function

'/ @brief Set user data attached to a connected peer
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 ' @param user_data [in] User data
 '
 ' @return 1 on succes, 0 otherwise
 '/
function MySrv_PeerSetUserData (mySrv as mySrv_t ptr, peer_id as integer, user_data as any ptr) as integer MYSOCK_EXPORT
    if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return 0
    
    mySrv->peers[peer_id].user_data = user_data
    return 1
end function

'/ @brief Get user data attached to a connected peer
 '
 ' @param mySrv [in] Server pointer
 ' @param peer_id [in] Peer ID
 '
 ' @return User data on succes, 0 otherwise
 '/
function MySrv_PeerGetUserData (mySrv as mySrv_t ptr, peer_id as integer) as any ptr MYSOCK_EXPORT
    if not PEER_VALID(mySrv, peer_id) or not PEER_CONNECTED(mySrv, peer_id) then return 0
    
    return mySrv->peers[peer_id].user_data
end function

' ---------------------------------------------------------------------------- '

end extern
