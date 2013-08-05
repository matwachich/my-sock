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

#define MYSOCK_ISVALID(sock) sock <> -1

' ---------------------------------------------------------------------------- '

extern "C"

' ---------------------------------------------------------------------------- '

'' @brief Permits an incoming connection attempt on a socket
 '
 ' @param sock [in] Socket ID (MyTcp_Listen)
 '
 ' @return Newly connected Socket ID, or -1 if no pending connection
 '/
function	MyTcp_Accept		(sock as MYSOCK) as MYSOCK MYSOCK_EXPORT
    dim as sockaddr_storage addr
    dim as uinteger addr_len = sizeof(addr)
    
    return accept(sock, cast(sockaddr ptr, @addr), @addr_len)
end function

'' @brief Closes a TCP socket
 '
 ' @param sock [in] Socket ID
 '
 ' @return 1
 '/
function	MyTcp_CloseSocket	(sock as MYSOCK) as integer MYSOCK_EXPORT
    if not MYSOCK_ISVALID(sock) then return 0
    ' ---
    closesocket(sock)
    return 1
end function

'' @brief Create a socket and connect it to an existing server
 '
 ' @param host [in] Host name or IP address of the server to connect to
 ' @param port [in] Port number to connect to
 ' @param protocol [in] IP version to use (Enum protocol_e)
 '	MYSOCK_PROT_AUTO - Auto-select (will select IPv6 first if available)
 '	MYSOCK_PROT_IPV4 - Force IPv4
 '	MYSOCK_PROT_IPV6 - Force IPv6
 ' @param timeout [in] Time out (in seconds) befor return a failed connect attempt
 '
 ' @return Connected Socket ID on succes, -1 otherwise
 '/
function	MyTcp_Connect		(host as zstring, port as ushort, protocol as protocol_e, timeout as uinteger) as MYSOCK MYSOCK_EXPORT
    dim as addrinfo hints:
    clear(hints, 0, sizeof(hints))
    dim as addrinfo ptr list, to_free
    
    hints.ai_family = prot2af(protocol)
    hints.ai_socktype = SOCK_STREAM
    
    if getaddrinfo(host, str(port), @hints, @list) <> 0 then
        #ifdef MYSOCK_DEBUG
        print "! MyTcp_Connect failed - (getaddrinfo failed - err"; WSAGetLastError() ;")"
        #endif
        return INVALID_SOCKET
    end if
    if list = 0 then
        #ifdef MYSOCK_DEBUG
        print "! MyTcp_Connect failed - (getaddrinfo returned empty list - err"; WSAGetLastError() ;")"
        #endif
        return INVALID_SOCKET
    end if
    
    to_free = list
    
    dim as ulong yes = 1
    dim as MYSOCK sock = INVALID_SOCKET
    dim as timeval tv
    dim as fd_set set
    
    do
        sock = socket_(list->ai_family, list->ai_socktype, list->ai_protocol)
        if sock = INVALID_SOCKET then goto try_next
        
        if ioctlsocket(sock, FIONBIO, @yes) <> 0 then goto try_next
        
        if connect(sock, list->ai_addr, list->ai_addrlen) <> 0 and WSAGetLastError() <> WSAEWOULDBLOCK then goto try_next
        
        tv.tv_sec = timeout
        tv.tv_usec = 0
        
        FD_ZERO(@set)
        FD_SET_(sock, @set)
        
        if select_(0, 0, @set, 0, @tv) <= 0 then
            #ifdef MYSOCK_DEBUG
            print "! MyTcp_Connect - select timedout"
            #endif
            goto try_next
        end if
        
        ' succes!
        freeaddrinfo(to_free)
        exit do
        
        try_next:
        if sock <> INVALID_SOCKET then closesocket(sock)
        sock = INVALID_SOCKET
        ' ---
        list = list->ai_next
        if list = 0 then
            #ifdef MYSOCK_DEBUG
            print "! MyTcp_Connect failed - (unable to create/connect socket - err"; WSAGetLastError() ;")"
            #endif
            freeaddrinfo(to_free)
            return INVALID_SOCKET
        end if
    loop
    
    return sock
end function

'' @brief Creates a socket listening for an incoming connection
 '
 ' @param port [in] Port number to listen
 ' @param protocol [in] IP version to use (Enum protocol_e)
 '	MYSOCK_PROT_AUTO - Auto-select (will select IPv6 first if available)
 '	MYSOCK_PROT_IPV4 - Force IPv4
 '	MYSOCK_PROT_IPV6 - Force IPv6
 ' @param max_conn [in] Maximum length of the queue of pending connections
 '
 ' @return Listening Socket ID on succes, -1 otherwise
 '/
function	MyTcp_Listen		(port as ushort, protocol as protocol_e, max_conn as uinteger) as MYSOCK MYSOCK_EXPORT
    dim as addrinfo hints
    clear(hints, 0, sizeof(hints))
    dim as addrinfo ptr list, to_free
    
    hints.ai_family = prot2af(protocol)
    hints.ai_socktype = SOCK_STREAM
    hints.ai_flags = AI_PASSIVE
    
    if getaddrinfo(NULL, str(port), @hints, @list) <> 0 then
        #ifdef MYSOCK_DEBUG
        print "! MyTcp_Listen failed - (getaddrinfo failed - err" ; WSAGetLastError() ; ")"
        #endif
        return INVALID_SOCKET
    end if
    if list = 0 then
        #ifdef MYSOCK_DEBUG
        print "! MyTcp_Listen failed - (getaddrinfo returned empty list - err" ; WSAGetLastError() ; ")"
        #endif
        return INVALID_SOCKET
    end if
    
    to_free = list

    dim as MYSOCK sock = INVALID_SOCKET
    dim as byte yes = 1
    dim as ulong yes2 = 1
    
    do
        sock = socket_(list->ai_family, list->ai_socktype, list->ai_protocol)
        if sock = INVALID_SOCKET then goto try_next
        
        if _
            setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, @yes, sizeof(yes)) = -1 or _	' reuse address
            ioctlsocket(sock, FIONBIO, @yes2) = -1 or _	' async mode
            bind(sock, list->ai_addr, list->ai_addrlen) = -1 or _
            listen(sock, max_conn) = -1 _
        then
            goto try_next
        end if
        
        freeaddrinfo(to_free)
        exit do ' success
        
        try_next:
        if sock <> INVALID_SOCKET then closesocket(sock)
        sock = INVALID_SOCKET
        ' ---
        list = list->ai_next
        if list = NULL then
            #ifdef MYSOCK_DEBUG
            print "! MyTcp_Listen failed - (unable to create/bind/listen socket - err " ; WSAGetLastError() ; ")"
            #endif
            freeaddrinfo(to_free)
            return INVALID_SOCKET
        end if
    loop
    
    return sock
end function

'' @brief Receives data from a connected socket
 '
 ' @param sock [in] Socket ID
 ' @param data_ [out] data buffer to fill with received data
 ' @param data_len [in] Size of the buffer (in bytes)
 '
 ' @return 0 or received bytes count if succes, -1 otherwise
 '/
function	MyTcp_Recv			(sock as MYSOCK, data_ as ubyte ptr, data_len as uinteger) as integer MYSOCK_EXPORT
    dim as integer ret = recv(sock, data_, data_len, 0)
    select case ret
        case is > 0 ' data received
            return ret
        case 0 ' disconnected
            return -1
        case -1
            if WSAGetLastError() = WSAEWOULDBLOCK then
                return 0 ' no data
            else
                return -1 ' error
            end if
    end select
end function

'' @brief Sends data on a connected socket
 '
 ' @param sock [in] Socket ID
 ' @param data_ [in] Pointer to a buffer containing the data to send
 ' @param data_len [in] Size of the buffer (in bytes)
 '
 ' @return Bytes sent on succes, -1 otherwise (error)
 '/
function	MyTcp_Send			(sock as MYSOCK, data_ as ubyte ptr, data_len as uinteger) as integer MYSOCK_EXPORT
    dim as integer total = 0, remain = data_len, n = 0

    do while total < data_len
        n = send(sock, @data_[total], remain, 0)
        if n = -1 and WSAGetLastError() <> WSAEWOULDBLOCK then return -1 ' error
        total += n
        remain -= n
    loop

    return total
end function

' ---------------------------------------------------------------------------- '

end extern