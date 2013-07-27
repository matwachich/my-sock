#ifndef __MYSOCK_BI__
#define __MYSOCK_BI__

#inclib "mysock"

extern "C"

' ---
' Enumerations
enum protocol_e
	MYSOCK_PROT_AUTO ' AF_UNSPEC
	MYSOCK_PROT_IPV4 ' AF_INET
	MYSOCK_PROT_IPV6 ' AF_INET6
end enum

' ---
' Type definitions
type MYSOCK as integer

type mySrv_t as _mySrv_t
type myCln_t as _myCln_t

type mySrvOnConnectProc as sub (mySrv as mySrv_t ptr, peer_id as integer)
type mySrvOnDisconnectProc as sub (mySrv as mySrv_t ptr, peer_id as integer)
type mySrvOnRecvProc as sub (mySrv as mySrv_t ptr, peer_id as integer, data_ as ubyte ptr, data_len as uinteger)

type mySrvIterateProc as function (mySrv as mySrv_t ptr, peer_id as integer, user_data as any ptr) as integer

type myClnOnDisconnectProc as sub (myCln as myCln_t ptr)
type myClnOnRecvProc as sub (myCln as myCln_t ptr, data_ as byte ptr, data_len as uinteger)

' ---
' ---
' Startup/Shutdown
declare function MySock_Startup		() as integer
declare function MySock_Shutdown	() as integer

' ---
' Helper functions
declare function 	MySock_Host2ip		(host as zstring, protocol as protocol_e, ip as zstring, ip_len as uinteger) as integer
declare function 	MySock_Host2ipStr	(host as zstring, protocol as protocol_e) as string
declare sub 		MySock_MyHost		(host as zstring, host_len as uinteger)
declare function 	MySock_MyHostStr	() as string

' ---
' Server functions
declare function 	MySrv_Create			(max_peers as uinteger, protocol as protocol_e) as mySrv_t ptr
declare function 	MySrv_Destroy			(mySrv as mySrv_t ptr) as integer
declare function 	MySrv_Start				(mySrv as mySrv_t ptr, port as ushort) as integer
declare function 	MySrv_Stop				(mySrv as mySrv_t ptr) as integer
declare function 	MySrv_IsStarted			(mySrv as mySrv_t ptr) as integer

declare sub 		MySrv_SetProtocol		(mySrv as mySrv_t ptr, protocol as protocol_e)
declare function	MySrv_GetProtocol		(mySrv as mySrv_t ptr) as integer
declare function	MySrv_GetAddr			(mySrv as mySrv_t ptr, ip as zstring, ip_len as uinteger, port as ushort ptr) as integer
declare function	MySrv_GetAddrStr		(mySrv as mySrv_t ptr, with_port as integer) as string
declare sub 		MySrv_SetDefBuffLen		(mySrv as mySrv_t ptr, default_buff_len as uinteger)
declare function 	MySrv_GetDefBuffLen		(mySrv as mySrv_t ptr) as uinteger
declare sub 		MySrv_SetDefKeepAlive	(mySrv as mySrv_t ptr, timeout as uinteger, interval as uinteger)
declare sub 		MySrv_GetDefKeepAlive	(mySrv as mySrv_t ptr, timeout as uinteger ptr, interval as uinteger ptr)
declare function	MySrv_GetSocket			(mySrv as mySrv_t ptr) as integer
declare sub 		MySrv_SetUserData		(mySrv as mySrv_t ptr, user_data as any ptr)
declare function	MySrv_GetUserData		(mySrv as mySrv_t ptr) as any ptr

declare sub 		MySrv_SetCallbacks		(mySrv as mySrv_t ptr, onConnect as mySrvOnConnectProc, onDisconnect as mySrvOnDisconnectProc, onRecv as mySrvOnRecvProc)
declare sub 		MySrv_Process			(mySrv as mySrv_t ptr)

declare function 	MySrv_PeerSend			(mySrv as mySrv_t ptr, peer_id as integer, data_ as ubyte ptr, data_len as uinteger) as integer
declare function 	MySrv_Broadcast			(mySrv as mySrv_t ptr, data_ as ubyte ptr, data_len as uinteger) as integer
declare function 	MySrv_Close				(mySrv as mySrv_t ptr, peer_id as integer) as integer
declare function 	MySrv_CloseAll			(mySrv as mySrv_t ptr) as integer

declare function 	MySrv_PeersCount		(mySrv as mySrv_t ptr) as integer
declare function 	MySrv_PeersGetAll		(mySrv as mySrv_t ptr, peer_ids as integer ptr, peers_ids_size as uinteger) as integer
declare function 	MySrv_PeersIterate		(mySrv as mySrv_t ptr, callback as mySrvIterateProc, user_data as any ptr) as integer

declare function	MySrv_PeerGetAddr		(mySrv as mySrv_t ptr, peer_id as integer, ip as zstring, ip_len as integer, port as ushort ptr) as integer
declare function	MySrv_PeerGetAddrStr	(mySrv as mySrv_t ptr, peer_id as integer, with_port as integer) as string
declare function 	MySrv_PeerSetBuffLen	(mySrv as mySrv_t ptr, peer_id as integer, buff_len as uinteger) as integer
declare function 	MySrv_PeerGetBuffLen	(mySrv as mySrv_t ptr, peer_id as integer) as uinteger
declare sub 		MySrv_PeerSetKeepAlive	(mySrv as mySrv_t ptr, peer_id as integer, timeout as uinteger, interval as uinteger)
declare sub 		MySrv_PeerGetKeepAlive	(mySrv as mySrv_t ptr, peer_id as integer, timeout as uinteger ptr, interval as uinteger ptr)
declare function	MySrv_PeerGetSocket		(muSrv as mySrv_t ptr, peer_id as integer) as integer
declare function 	MySrv_PeerSetUserData	(mySrv as mySrv_t ptr, peer_id as integer, user_data as any ptr) as integer
declare function 	MySrv_PeerGetUserData	(mySrv as mySrv_t ptr, peer_id as integer) as any ptr

' ---
' Client functions
declare function 	MyCln_Create		(host as zstring, port as ushort, protocol as protocol_e) as myCln_t ptr
declare function 	MyCln_Destroy		(myCln as myCln_t ptr) as integer
declare function 	MyCln_Connect		(myCln as myCln_t ptr, timeout as uinteger) as integer
declare function 	MyCln_Close			(myCln as myCln_t ptr) as integer
declare function 	MyCln_IsConnected	(myCln as myCln_t ptr) as integer

declare sub 		MyCln_SetProtocol	(myCln as myCln_t ptr, protocol as protocol_e)
declare function	MyCln_GetProtocol	(myCln as myCln_t ptr) as integer
declare sub 		MyCln_SetHost		(myCln as myCln_t ptr, host as zstring, port as ushort)
declare sub 		MyCln_GetHost		(myCln as myCln_t ptr, host as zstring, host_len as uinteger, port as ushort ptr)
declare function 	MyCln_GetHostStr	(myCln as myCln_t ptr, with_port as integer) as string
declare sub 		MyCln_GetSrvIp		(myCln as myCln_t ptr, ip as zstring, ip_len as uinteger, port as ushort ptr)
declare function 	MyCln_GetSrvIpStr	(myCln as myCln_t ptr, with_port as integer) as string

declare sub 		MyCln_SetCallbacks	(myCln as myCln_t ptr, onDisconnect as myClnOnDisconnectProc, onRecv as myClnOnRecvProc)
declare sub 		MyCln_Process		(myCln as myCln_t ptr)

declare function 	MyCln_Send			(myCln as myCln_t ptr, data_ as ubyte ptr, data_len as uinteger) as integer

declare function	MyCln_SetBuffLen	(myCln as myCln_t ptr, buff_len as uinteger) as integer
declare function	MyCln_GetBuffLen	(myCln as myCln_t ptr) as uinteger
declare function 	MyCln_SetKeepAlive 	(myCln as myCln_t ptr, timeout as uinteger, interval as uinteger) as integer
declare sub 		MyCln_GetKeepAlive 	(myCln as myCln_t ptr, timeout as uinteger ptr, interval as uinteger ptr)
declare function	MyCln_GetSocket		(myCln as myCln_t ptr) as integer
declare sub 		MyCln_SetUserData 	(myCln as myCln_t ptr, user_data as any ptr)
declare function 	MyCln_GetUserData 	(myCln as myCln_t ptr) as any ptr

' ---
end extern

#endif ' __MYSOCK_BI__