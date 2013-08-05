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
#error MySock is designed for windows only!
#endif

#include "mysock.bi"
#include "internals.bi"

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
    as MYSIZE recv_buff_len
    as MYSIZE recv_buff_ofset
    'as MYSIZE packet_len
    'as MYSIZE total_recv
    
    'as byte is_stream
    as byte is_receiving
    
    as double recv_timer
    as uinteger recv_timeout
    
    as uinteger keepalive_timeout
    as uinteger keepalive_interval
    
    as myClnOnDisconnectProc onDisconnect
    as myClnOnPacketRecvProc onPacketRecv
    as myClnOnReceivingProc onReceiving
    as myClnOnTimeOutProc onTimeOut
    
    as any ptr user_data
end type

' ---------------------------------------------------------------------------- '

extern "C"

' ---------------------------------------------------------------------------- '

'/ @brief Create a TCP Client
 '
 ' @param host [in] Host name or IP address of the server
 ' @param port [in] Port number of the server
 ' @param protocol [in] IP version to use when resolving a host name (Enum protocol_e)
 '	MYSOCK_PROT_AUTO - Auto-select (will select IPv6 first if available)
 '	MYSOCK_PROT_IPV4 - Force IPv4
 '	MYSOCK_PROT_IPV6 - Force IPv6
 '
 ' @return Client pointer (myCln_t ptr) on succes, 0 otherwise
 '/
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
    myCln->recv_buff_ofset = 0
    ' ---
    'myCln->is_stream = 0
    myCln->is_receiving = 0
    ' ---
    myCln->recv_timeout = MYSOCK_DEF_RECV_TIMEOUT
    myCln->recv_timer = 0
    ' ---
    myCln->keepalive_timeout = 0
    myCln->keepalive_interval = 0
    ' ---
    myCln->onDisconnect = 0
    myCln->onPacketRecv = 0
    myCln->onReceiving = 0
    myCln->onTimeOut = 0
    ' ---
    return myCln
end function

'/ @brief Destroy a TCP Client
 '
 ' @param myCln [in] Client pointer
 '
 ' @return 1
 '/
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

'/ @brief Connect a TCP Client to it's server
 '
 ' If a host name was passed to MyCln_Create, then this function will make a DNS lookup
 '
 ' @param myCln [in] Client pointer
 ' @param timeout [in] Time out (in seconds) befor returning a failed connect attempt
 '
 ' @return 1 on succes, -1 if timed out, 0 otherwise
 '/
function MyCln_Connect (myCln as myCln_t ptr, timeout as uinteger) as integer MYSOCK_EXPORT
    if CLN_CONNECTED(myCln) then return 0
    ' ---
    dim as addrinfo hints
    clear(hints, 0, sizeof(hints))
    dim as addrinfo ptr list, to_free
    
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
    
    to_free = list
    
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
        freeaddrinfo(to_free)
        exit do
        
        try_next:
        if myCln->sock <> INVALID_SOCKET then closesocket(myCln->sock)
        myCln->sock = INVALID_SOCKET
        ' ---
        list = list->ai_next
        if list = 0 then
            #ifdef MYSOCK_DEBUG
            print "! MyCln_Connect failed - (unable to create/connect socket - err " ; WSAGetLastError() ; ")"
            #endif
            freeaddrinfo(to_free)
            return -1
        end if
    loop
    
    myCln->recv_buff = callocate(1, sizeof(ulong))
    myCln->recv_buff_len = sizeof(ulong)
    
    #ifdef MYSOCK_DEBUG
    print "> Client @"; myCln; " connected to "; str(myCln->ip); ":"; myCln->port
    #endif
    return 1
end function

'/ @brief Close a connected TCP Client
 '
 ' This function will call MyCln_Process once, in order to call the myClnOnDisconnect callback
 '
 ' @param myCln [in] Client pointer
 '
 ' @return 1 on succes, 0 otherwise
 '/
function MyCln_Close (myCln as myCln_t ptr) as integer MYSOCK_EXPORT
    if not CLN_CONNECTED(myCln) then return 0
    
    shutdown(myCln->sock, 1)
    MyCln_Process(myCln)
    
    return 1
end function

'/ @brief Check if a TCP Client is connected to it's server
 '
 ' @param myCln [in] Client pointer
 '
 ' @return 1 if connected, 0 otherwise
 '/
function MyCln_IsConnected (myCln as myCln_t ptr) as integer MYSOCK_EXPORT
    if CLN_CONNECTED(myCln) then return 1
    return 0
end function

'/ @brief Set TCP Client's protocol used in host name resolving
 '
 ' @param myCln [in] Client pointer
 ' @param protocol [in] IP version to use when resolving a host name (Enum protocol_e)
 '	MYSOCK_PROT_AUTO - Auto-select (will select IPv6 first if available)
 '	MYSOCK_PROT_IPV4 - Force IPv4
 '	MYSOCK_PROT_IPV6 - Force IPv6
 '/
sub MyCln_SetProtocol (myCln as myCln_t ptr, protocol as protocol_e) MYSOCK_EXPORT
    myCln->protocol = prot2af(protocol)
end sub

'/ @brief Get TCP Client's protocol used in host name resolving
 '
 ' @param myCln [in] Client pointer
 '
 ' @return MYSOCK_PROT_AUTO, MYSOCK_PROT_IPV4 or MYSOCK_PROT_IPV6
 '/
function MyCln_GetProtocol (myCln as myCln_t ptr) as integer MYSOCK_EXPORT
    return af2prot(myCln->protocol)
end function

'/ @brief Set TCP Client's host/ip and port
 '
 ' @param myCln [in] Client pointer
 ' @param host [in] Host name or IP address of the server
 ' @param port [in] Port number of the server
 '/
sub MyCln_SetHost (myCln as myCln_t ptr, host as zstring, port as ushort) MYSOCK_EXPORT
    if myCln->host <> 0 then deallocate(myCln->host)
    
    dim as integer l = len(host)
    myCln->host = callocate(l + 1, sizeof(zstring))
    if myCln->host = 0 then return
    *(myCln->host) = host
    ' ---
    myCln->port = port
end sub

'/ @brief Get TCP Client's host/ip and port (C-style)
 '
 ' @param myCln [in] Client pointer
 ' @param host [out] Buffer that will contain host/ip passed to MyCln_Create
 ' @param host_len [in] Size of the buffer
 ' @param port [in] Pointer to an UShort variable that will contain server's port number (as passed to MyCln_Create)
 '/
sub MyCln_GetHost (myCln as myCln_t ptr, host as zstring, host_len as MYSIZE, port as ushort ptr) MYSOCK_EXPORT
    host = left(*(myCln->host), host_len - 1)
    if port <> 0 then *port = myCln->port
end sub

'/ @brief Get TCP Client's host/ip and port (FB String)
 '
 ' @param myCln [in] Client pointer
 ' @param with_port [in] Set to non 0 to append port number to the end of the returned String
 '
 ' @return String containing the host/ip and optionally the port number (host/ip:port)
 '/
function MyCln_GetHostStr (myCln as myCln_t ptr, with_port as integer) as string MYSOCK_EXPORT
    dim as string s = *myCln->host
    if with_port <> 0 then
        if instr(s, ":") then
            s = "[" + s + "]"
        end if
        s += ":" + str(myCln->port)
    end if
    return s
end function

'/ @brief Get server's resolved IP address and port (C-style)
 '
 ' The server's IP address is only available for a connected TCP Client
 '
 ' @param myCln [in] Client pointer
 ' @param ip [out] Buffer that will contain server's IP address
 ' @param ip_len [in] Size of the buffer
 ' @param port [out] Pointer to an UShort variable that will contain the server's port number
 '/
sub MyCln_GetSrvIp (myCln as myCln_t ptr, ip as zstring, ip_len as MYSIZE, port as ushort ptr) MYSOCK_EXPORT
    'if ip <> 0 and ip_len > 0 then
        ip = left(myCln->ip, ip_len - 1)
    'end if
    if port <> 0 then
        *port = myCln->port
    end if
end sub

'/ @brief Get server's resolved IP address and port (FB String)
 '
 ' The server's IP address is only available for a connected TCP Client
 '
 ' @param myCln [in] Client pointer
 ' @param with_port [in] Set to non 0 to append the port number to the end of the returned String
 '
 ' @return String containing the server's IP address, and optionaly it's port number on succes, empty string ("") otherwise
 '/
function MyCln_GetSrvIpStr (myCln as myCln_t ptr, with_port as integer) as string MYSOCK_EXPORT
    dim as string s = str(myCln->ip)
    if with_port <> 0 then
        if instr(s, ":") then
            s = "[" + s + "]"
        end if
        s += ":" + str(myCln->port)
    end if
    return s
end function

'/ @brief Set one callback function for a TCP Client
 '
 ' @param myCln [in] Client pointer
 ' @param callback [in] Which callback to set
 '  MYSOCK_CB_DISCONNECT    Set the onDisconnect callback (myClnOnDisconnectProc)
 '  MYSOCK_CB_PACKETRECV    Set the onPacketRecv callback (myClnOnPacketRecvProc)
 '  MYSOCK_CB_RECEIVING     Set the onReceiving callback (myClnOnReceivingProc)
 '  MYSOCK_CB_TIMEOUT       Set the onTimeOut callback (myClnOnTimeOutProc)
 ' @param proc [in] Callback function pointer
 '/
sub MyCln_SetCallback (myCln as myCln_t ptr, callback as callback_e, proc as any ptr)
    select case callback
        case MYSOCK_CB_DISCONNECT
            myCln->onDisconnect = proc
        case MYSOCK_CB_PACKETRECV
            myCln->onPacketRecv = proc
        case MYSOCK_CB_RECEIVING
            myCln->onReceiving = proc
        case MYSOCK_CB_TIMEOUT 
            myCln->onTimeOut = proc
    end select
end sub

'/ @brief Set TCP Client's callbacks
 '
 ' @param myCln [in] Client pointer
 ' @param onDisconnect [in] Pointer to a myClnOnDisconnectProc
 '	sub (myCln as myCln_t ptr, partial_data as ubyte ptr, data_len as MYSIZE, excepted_len as MYSIZE)
 ' @param onPacketRecv [in] Pointer to a myClnOnPacketRecvProc
 '	sub (myCln as myCln_t ptr, data_ as ubyte ptr, data_len as MYSIZE)
 ' @param onReceiving [in] Pointer to a myClnOnReceivingProc
 '	sub (myCln as myCln_t ptr, received_bytes as MYSIZE, total_bytes as MYSIZE)
 ' @param onTimeOut [in] Pointer to a myClnOnTimeOutProc
 '  sub (myCln as myCln_t ptr, partial_data as ubyte ptr, data_len as MYSIZE, excepted_len as MYSIZE)
 '/
sub MyCln_SetCallbacks (myCln as myCln_t ptr, _
                        onDisconnect as myClnOnDisconnectProc, _
                        onPacketRecv as myClnOnPacketRecvProc, _
                        onReceiving as myClnOnReceivingProc, _
                        onTimeOut as myClnOnTimeOutProc) MYSOCK_EXPORT
    myCln->onDisconnect = onDisconnect
    myCln->onPacketRecv = onPacketRecv
    myCln->onReceiving = onReceiving
    myCln->onTimeOut = onTimeOut
end sub

'/ @brief Process a TCP Client. Receives data and call callbacks
 '
 ' @param myCln [in] Client pointer
 '/
sub MyCln_Process (myCln as myCln_t ptr) MYSOCK_EXPORT
    if not CLN_CONNECTED(myCln) then return
    ' ---
    dim as byte disconnect = 0
    ' ---
    dim as integer ret = recv( _
        myCln->sock, _
        myCln->recv_buff + myCln->recv_buff_ofset, _
        myCln->recv_buff_len - myCln->recv_buff_ofset, _
        0)
    ' ---
    select case ret
        case is > 0
            myCln->recv_buff_ofset += ret
            ' re-init recv timer
            myCln->recv_timer = timer()
            ' ---
            if myCln->is_receiving = 0 then ' receiving packet size
                if myCln->recv_buff_ofset = sizeof(ulong) then ' complete packet size
                    dim as ulong packet_size = *cast(ulong ptr, myCln->recv_buff)
                    ' ---
                    myCln->recv_buff = reallocate(myCln->recv_buff, packet_size)
                    myCln->recv_buff_len = packet_size
                    myCln->recv_buff_ofset = 0
                    myCln->is_receiving = 1
                    ' ---
                    if myCln->onReceiving <> 0 then
                        myCln->onReceiving(myCln, 0, packet_size)
                    end if
                end if
            else
                if myCln->onReceiving <> 0 then
                    myCln->onReceiving(myCln, myCln->recv_buff_ofset, myCln->recv_buff_len)
                end if
                ' ---
                if myCln->recv_buff_ofset = myCln->recv_buff_len then ' packet complete
                    if myCln->onPacketRecv <> NULL then
                        myCln->onPacketRecv(myCln, myCln->recv_buff, myCln->recv_buff_len)
                    end if
                    ' ---
                    ' reset peer to pakce-size-wait state
                    myCln->recv_buff = reallocate(myCln->recv_buff, sizeof(ulong))
                    myCln->recv_buff_len = sizeof(ulong)
                    myCln->recv_buff_ofset = 0
                    myCln->is_receiving = 0
                end if
            end if
        case 0
            disconnect = 1
        case -1
            if WSAGetLastError() <> WSAEWOULDBLOCK then
                disconnect = 1
            end if
    end select
    ' ---
    ' check recv time out
    if myCln->recv_buff_ofset > 0 and _
        timer() - myCln->recv_timer > myCln->recv_timeout then
        ' ---
        if myCln->onTimeOut <> 0 then
            myCln->onTimeOut(myCln, myCln->recv_buff, myCln->recv_buff_ofset, myCln->recv_buff_len)
            myCln->is_receiving = 0 ' so there will be no partial data passed to onDisconnect
        end if
        ' ---
        disconnect = 1
    end if
    ' ---
    if disconnect then
        if myCln->onDisconnect then
            if myCln->is_receiving then
                myCln->onDisconnect(myCln, myCln->recv_buff, myCln->recv_buff_ofset, myCln->recv_buff_len)
            else
                myCln->onDisconnect(myCln, 0, 0, 0)
            end if
        end if
        ' ---
        closesocket(myCln->sock)
        myCln->sock = INVALID_SOCKET
        ' ---
        if myCln->recv_buff <> 0 then deallocate(myCln->recv_buff): myCln->recv_buff = 0
        ' ---
        myCln->ip = ""
    end if
end sub

'/ @brief Send data to a connected Server
 '
 ' @param myCln [in] Client pointer
 ' @param data_ [in] Data to send
 ' @param data_len [in] Size of the data (in bytes)
 '
 ' @return Total bytes sent if succes, 0 if client is not connected, -1 if error while calling send()
 '/
function MyCln_Send (myCln as myCln_t ptr, data_ as ubyte ptr, data_len as MYSIZE) as integer MYSOCK_EXPORT
    if not CLN_CONNECTED(myCln) then return 0
    
    ' send packet size
    if send(myCln->sock, cast(ubyte ptr, @data_len), sizeof(ulong), 0) <> sizeof(ulong) then return -1
    
    dim as integer total = 0, remain = data_len, n = 0

    do while total < data_len
        n = send(myCln->sock, @data_[total], remain, 0)
        if n = -1 and WSAGetLastError() <> WSAEWOULDBLOCK then return -1
        total += n
        remain -= n
    loop

    return total
end function

'/ @brief Set TCP Client's receive timeout
 '
 ' When a packet size or packet data is being received, and no data has been received
 ' for `timeout` seconds, then the client is disconnected and the myClnOnTimeOutProc is
 ' called with the partial received data
 '
 ' @param myCln [in] Client pointer
 ' @param timeout [in] Receive timeout (in seconds)
 '/
sub MyCln_SetRecvTimeOut (myCln as myCln_t ptr, timeout as uinteger)
    myCln->recv_timeout = timeout
end sub

'/ @brief Get TCP Client's receive timeout
 '
 ' @param myCln [in] Client pointer
 '
 ' @return Receive timeout (in seconds)
 '/
function MyCln_GetRecvTimeOut (myCln as myCln_t ptr) as uinteger
    return myCln->recv_timeout
end function

'/ @brief Set TCP Client's keepalive status and values
 '
 ' @param myCln [in] Client pointer
 ' @param timeout [in] Keep alive timeout (in seconds)
 ' @param interval [in] Keep alive probes interval (in seconds)
 '
 '	If 'timeout' and 'interval' = 0 then the keepalive packets sending is deactivated.
 '	Otherwise, 'timeout' is the time with no activity until the first keep-alive packet is sent,
 '	and 'interval' is the delay between successive keep-alive packets
 '
 '	This function uses WSAIoctl & SIO_KEEPALIVE_VALS
 '
 ' @return 1 on succes, 0 otherwise
 '/
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

'/ @brief Get TCP Client's keepalive status and values
 '
 ' @param myCln [in] Client pointer
 ' @param timeout [out] Will contain Keep alive timeout (in seconds)
 ' @param interval [out] Will contain Keep alive interval (in seconds)
 '/
sub MyCln_GetKeepAlive (myCln as myCln_t ptr, timeout as uinteger ptr, interval as uinteger ptr) MYSOCK_EXPORT
    if timeout <> 0 then *timeout = myCln->keepalive_timeout
    if interval <> 0 then *interval = myCln->keepalive_interval
end sub

'/ @brief Get client's socket identifier
 '
 ' If the client is disconnected, then -1 is returned (INVALID_SOCKET)
 '
 ' @param myCln [in] Client pointer
 '
 ' @return Socket ID
 '/
function	MyCln_GetSocket		(myCln as myCln_t ptr) as integer
    return myCln->sock
end function

'/ @brief Set User data attached to a TCP Client
 '
 ' @param myCln [in] Client pointer
 ' @param user_data [in] User data
 '/
sub MyCln_SetUserData (myCln as myCln_t ptr, user_data as any ptr) MYSOCK_EXPORT
    myCln->user_data = user_data
end sub

'/ @brief Get User data attached to a TCP Client
 '
 ' @param myCln [in] Client pointer
 '
 ' @return User data
 '/
function MyCln_GetUserData (myCln as myCln_t ptr) as any ptr MYSOCK_EXPORT
    return myCln->user_data
end function

' ---------------------------------------------------------------------------- '

end extern

' ---------------------------------------------------------------------------- '
