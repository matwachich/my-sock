#ifndef __MYSOCK_INTERNALS__
#define __MYSOCK_INTERNALS__

#define MYSOCK_EXPORT export

' print debug output
'#define MYSOCK_DEBUG

' default receive timeout
#define MYSOCK_DEF_RECV_TIMEOUT 60 ' seconds

'/' DisconnectEx(sock, 0, 0, 0): '/
#define __closesocket(sock) closesocket(sock)

' ---------------------------------------------------------------------------- '

declare function sockaddr2ipport (addr as sockaddr_storage ptr, addr_len as integer, ip as zstring, ip_len as uinteger, port as ushort ptr) as integer
declare function sockaddr2str (addr as sockaddr_storage ptr, addr_len as integer, with_port as byte) as string

declare function af2prot (af as integer) as integer
declare function prot2af (prot as integer) as integer

#endif ' __MYSOCK_INTERNALS__