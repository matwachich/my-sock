#include-once
; #INDEX# =======================================================================================================================
; Title .........: MySock
; AutoIt Version : 3.3.8.1
; Description ...: WinSockets simple wrapper
; Author(s) .....: Matwachich
; Dll ...........: mysock.dll
; Remarks .......: Limitation of the AutoIt wrapper: you must use the same callbacks for all your servers/clients
; ===============================================================================================================================

; #DOC# =========================================================================================================================
; - You MUST call _MySock_Startup befor any other _MyXXX function, and _MySock_Shutdown at program termination
; - Every object created MUST be destroyed to avoir memory leak (_MySrv_Destroy, _MyCln_Destroy)
; - Callbacks definition:
;	mySrvOnConnectProc => _Func($pMySrv, $iPeerId)
;	mySrvOnDisconnectProc => _Func($pMySrv, $iPeerId)
;	mySrvOnRecvProc => _Func($pMySrv, $iPeerId, $bData)
;	mySrvIterateProc => _Func($pMySrv, $iPeerId, $pUserData) -> Return 0 to stope iterating, any other value will continue
;	myClnOnDisconnectProc => _Func($pMyCln)
;	myClnOnRecvProc => _Func($pMyCln, $bData)
; ===============================================================================================================================

; #CURRENT# =====================================================================================================================
;_MySock_Startup
;_MySock_Shutdown
;_MySock_Host2ip
;_MySock_MyHost
;_MySrv_Create
;_MySrv_Destroy
;_MySrv_Start
;_MySrv_Stop
;_MySrv_IsStarted
;_MySrv_SetProtocol
;_MySrv_GetProtocol
;_MySrv_GetAddr
;_MySrv_GetAddrStr
;_MySrv_SetDefBuffLen
;_MySrv_GetDefBuffLen
;_MySrv_SetDefKeepAlive
;_MySrv_GetDefKeepAlive
;_MySrv_GetSocket
;_MySrv_SetUserData
;_MySrv_GetUserData
;_MySrv_SetCallbacks
;_MySrv_Process
;_MySrv_PeerSend
;_MySrv_Broadcast
;_MySrv_Close
;_MySrv_CloseAll
;_MySrv_PeersCount
;_MySrv_PeersGetAll
;_MySrv_PeersIterate
;_MySrv_PeerGetAddr
;_MySrv_PeerGetAddrStr
;_MySrv_PeerSetBuffLen
;_MySrv_PeerGetBuffLen
;_MySrv_PeerSetKeepAlive
;_MySrv_PeerGetKeepAlive
;_MySrv_PeerGetSocket
;_MySrv_PeerSetUserData
;_MySrv_PeerGetUserData
;_MyCln_Create
;_MyCln_Destroy
;_MyCln_Connect
;_MyCln_Close
;_MyCln_IsConnected
;_MyCln_SetProtocol
;_MyCln_GetProtocol
;_MyCln_SetHost
;_MyCln_GetHost
;_MyCln_GetHostStr
;_MyCln_GetSrvIp
;_MyCln_SetCallbacks
;_MyCln_Process
;_MyCln_Send
;_MyCln_SetBuffLen
;_MyCln_GetBuffLen
;_MyCln_SetKeepAlive
;_MyCln_GetKeepAlive
;_MyCln_GetSocket
;_MyCln_SetUserData
;_MyCln_GetUserData
; ===============================================================================================================================

; #CONSTANTS# ===================================================================================================================
Enum _	; protocol_e
	$MYSOCK_PROT_AUTO, _
	$MYSOCK_PROT_IPV4, _
	$MYSOCK_PROT_IPV6
; ===============================================================================================================================

; ===============================================================================================================================
; Internals

; Global mySock dll handle
Global $__gMySock_hDll = -1

; Callbacks IDs
Enum _
	$MYSOCK_CB_SRV_ONCONNECT, _
	$MYSOCK_CB_SRV_ONDISCONNECT, _
	$MYSOCK_CB_SRV_ONRECV, _
	$MYSOCK_CB_CLN_ONDISCONNECT, _
	$MYSOCK_CB_CLN_ONRECV

Global $__gMySock_aCallbacks[5][3] = [ _
	[0, "none:cdecl", "ptr;int"], _				; mySrvOnConnectProc
	[0, "none:cdecl", "ptr;int"], _				; mySrvOnDisconnectProc
	[0, "none:cdecl", "ptr;int;ptr;uint"], _	; mySrvOnRecvProc
	[0, "none:cdecl", "ptr"], _					; myClnOnDisconnectProc
	[0, "none:cdecl", "ptr;ptr;uint"]]			; myClnOnRecvProc

; On recv special callbacks
Global $__gMySock_sSrvOnRecv = ""
Global $__gMySock_sClnOnRecv = ""

; ===============================================================================================================================

;~ declare function MySock_Startup () as integer
Func _MySock_Startup($sDllPath = "mysock.dll")
	If $__gMySock_hDll <> -1 Then Return -1
	; ---
	$__gMySock_hDll = DllOpen($sDllPath)
	If $__gMySock_hDll = -1 Then Return SetError(1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySock_Startup")
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySock_Startup)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function MySock_Shutdown () as integer
Func _MySock_Shutdown()
	If $__gMySock_hDll = -1 Then Return -1
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySock_Shutdown")
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySock_Shutdown)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	__MySock_FreeCallbacks()
	; ---
	DllClose($__gMySock_hDll)
	$__gMySock_hDll = -1
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySock_Host2ip		(host as zstring, protocol as protocol_e, ip as zstring, ip_len as uinteger) as integer
Func _MySock_Host2ip($sHost, $iProtocol = $MYSOCK_PROT_AUTO)
	If $__gMySock_hDll = -1 Then Return -1
	; ---
	Local $struct = DllStructCreate("char[256]")
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySock_Host2ip", "str", $sHost, "int", $iProtocol, "ptr", DllStructGetPtr($struct, 1), "uint", 256)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySock_Host2ip)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	If $ret[0] <> 1 Then Return ""
	Return DllStructGetData($struct, 1)
EndFunc

;~ declare sub 		MySock_MyHost		(host as zstring, host_len as uinteger)
Func _MySock_MyHost()
	If $__gMySock_hDll = -1 Then Return -1
	; ---
	Local $struct = DllStructCreate("char[256]")
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MySock_MyHost", "ptr", DllStructGetPtr($struct, 1), "uint", 256)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySock_MyHost)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return DllStructGetData($struct, 1)
EndFunc

; ===============================================================================================================================

;~ declare function 	MySrv_Create	(max_peers as uinteger, protocol as protocol_e) as mySrv_t ptr
Func _MySrv_Create($iMaxPeers, $iProtocol = $MYSOCK_PROT_AUTO)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "ptr:cdecl", "MySrv_Create", "uint", $iMaxPeers, "int", $iProtocol)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_Create)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_Destroy	(mySrv as mySrv_t ptr) as integer
Func _MySrv_Destroy($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_Destroy", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_Destroy)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_Start		(mySrv as mySrv_t ptr, port as ushort) as integer
Func _MySrv_Start($pMySrv, $iPort)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_Start", "ptr", $pMySrv, "ushort", $iPort)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_Start)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_Stop		(mySrv as mySrv_t ptr) as integer
Func _MySrv_Stop($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_Stop", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_Stop)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_IsStarted	(mySrv as mySrv_t ptr) as integer
Func _MySrv_IsStarted($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_IsStarted", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_IsStarted)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc


;~ declare sub 			MySrv_SetProtocol		(mySrv as mySrv_t ptr, protocol as protocol_e)
Func _MySrv_SetProtocol($pMySrv, $iProtocol)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MySrv_SetProtocol", "ptr", $pMySrv, "int", $iProtocol)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_SetProtocol)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc

;~ declare function		MySrv_GetProtocol		(mySrv as mySrv_t ptr) as integer
Func _MySrv_GetProtocol($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_GetProtocol", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_GetProtocol)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function		MySrv_GetAddr			(mySrv as mySrv_t ptr, ip as zstring, ip_len as uinteger, port as ushort ptr) as integer
Func _MySrv_GetAddr($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $struct = DllStructCreate("char[512]")
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_GetAddr", "ptr", $pMySrv, "ptr", DllStructGetPtr($struct), "uint", 512, "ushort*", 0)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_GetAddr)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	If $ret[0] = 0 Then Return 0
	; ---
	Local $aRet[2] = [DllStructGetData($struct, 1), $ret[4]]
	Return $aRet
EndFunc

Func _MySrv_GetAddrStr($pMySrv, $iWithPort)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $struct = DllStructCreate("char[512]")
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_GetAddr", "ptr", $pMySrv, "ptr", DllStructGetPtr($struct), "uint", 512, "ushort*", 0)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_GetAddr)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	If $ret[0] = 0 Then Return ""
	; ---
	Local $sRet = DllStructGetData($struct, 1)
	If $iWithPort Then
		If StringInStr($sRet, ":") Then $sRet = "[" & $sRet & "]"
		$sRet &= ":" & $ret[4]
	EndIf
	Return $sRet
EndFunc

;~ declare sub 			MySrv_SetDefBuffLen		(mySrv as mySrv_t ptr, default_buff_len as uinteger)
Func _MySrv_SetDefBuffLen($pMySrv, $iDefBuffLen)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "none:cdecl", "MySrv_SetDefBuffLen", "ptr", $pMySrv, "uint", $iDefBuffLen)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_SetDefBuffLen)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_GetDefBuffLen		(mySrv as mySrv_t ptr) as uinteger
Func _MySrv_GetDefBuffLen($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "uint:cdecl", "MySrv_GetDefBuffLen", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_GetDefBuffLen)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare sub 			MySrv_SetDefKeepAlive	(mySrv as mySrv_t ptr, timeout as uinteger, interval as uinteger)
Func _MySrv_SetDefKeepAlive($pMySrv, $iTimeOut, $iInterval)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MySrv_SetDefKeepAlive", "ptr", $pMySrv, "uint", $iTimeOut, "uint", $iInterval)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_SetDefKeepAlive)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc

;~ declare sub 			MySrv_GetDefKeepAlive	(mySrv as mySrv_t ptr, timeout as uinteger ptr, interval as uinteger ptr)
Func _MySrv_GetDefKeepAlive($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "none:cdecl", "MySrv_GetDefKeepAlive", "ptr", $pMySrv, "uint*", 0, "uint*", 0)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_GetDefKeepAlive)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Local $aRet[2] = [$ret[2], $ret[3]]
	Return $aRet
EndFunc

;~ declare function		MySrv_GetSocket			(mySrv as mySrv_t ptr) as integer
Func _MySrv_GetSocket($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_GetSocket", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_GetSocket)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare sub 			MySrv_SetUserData		(mySrv as mySrv_t ptr, user_data as any ptr)
Func _MySrv_SetUserData($pMySrv, $iUserData)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MySrv_SetUserData", "ptr", $pMySrv, "ptr", $iUserData)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_SetUserData)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc

;~ declare function		MySrv_GetUserData		(mySrv as mySrv_t ptr) as any ptr
Func _MySrv_GetUserData($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "ptr:cdecl", "MySrv_GetUserData", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_GetUserData)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc


;~ declare sub 			MySrv_SetCallbacks	(mySrv as mySrv_t ptr, onConnect as mySrvOnConnectProc, onDisconnect as mySrvOnDisconnectProc, onRecv as mySrvOnRecvProc)
Func _MySrv_SetCallbacks($pMySrv, $sOnConnect, $sOnDisconnect, $sOnRecv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "none:cdecl", "MySrv_SetCallbacks", "ptr", $pMySrv, _
		"ptr", __MySock_SetCallback($sOnConnect, $MYSOCK_CB_SRV_ONCONNECT), _
		"ptr", __MySock_SetCallback($sOnDisconnect, $MYSOCK_CB_SRV_ONDISCONNECT), _
		"ptr", __MySock_SetCallback($sOnRecv, $MYSOCK_CB_SRV_ONRECV) _
	)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_SetCallbacks)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc

;~ declare sub 			MySrv_Process		(mySrv as mySrv_t ptr)
Func _MySrv_Process($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MySrv_Process", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_Process)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc


;~ declare function 	MySrv_PeerSend	(mySrv as mySrv_t ptr, peer_id as integer, data_ as byte ptr, data_len as uinteger) as integer
Func _MySrv_PeerSend($pMySrv, $iPeerId, $bData)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $len = BinaryLen($bData)
	Local $struct = DllStructCreate("byte[" & $len & "]")
	DllStructSetData($struct, 1, $bData)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "none:cdecl", "MySrv_PeerSend", "ptr", $pMySrv, "int", $iPeerId, "ptr", DllStructGetPtr($struct, 1), "uint", $len)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerSend)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_Broadcast	(mySrv as mySrv_t ptr, data_ as byte ptr, data_len as uinteger) as integer
Func _MySrv_Broadcast($pMySrv, $bData)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $len = BinaryLen($bData)
	Local $struct = DllStructCreate("byte[" & $len & "]")
	DllStructSetData($struct, 1, $bData)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_Broadcast", "ptr", $pMySrv, "ptr", DllStructGetPtr($struct, 1), "uint", $len)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_Broadcast)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_Close		(mySrv as mySrv_t ptr, peer_id as integer) as integer
Func _MySrv_Close($pMySrv, $iPeerId)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_Close", "ptr", $pMySrv, "int", $iPeerId)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_Close)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_CloseAll	(mySrv as mySrv_t ptr) as integer
Func _MySrv_CloseAll($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_CloseAll", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_CloseAll)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc


;~ declare function 	MySrv_PeersCount	(mySrv as mySrv_t ptr) as integer
Func _MySrv_PeersCount($pMySrv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_PeersCount", "ptr", $pMySrv)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeersCount)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_PeersGetAll	(mySrv as mySrv_t ptr, peer_ids as integer ptr, peers_ids_size as uinteger) as integer
Func _MySrv_PeersGetAll($pMySrv, $iMax = -1)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	If $iMax = -1 Then $iMax = _MySrv_PeersCount($pMySrv)
	If $iMax = 0 Then Return 0
	; ---
	Local $struct = DllStructCreate("int[" & $iMax & "]")
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_PeersGetAll", "ptr", $pMySrv, "ptr", DllStructGetPtr($struct, 1), "uint", $iMax)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeersGetAll)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	If $ret[0] = 0 Then Return 0
	; ---
	Local $aRet[$ret[0] + 1]
	$aRet[0] = $ret[0]
	For $i = 1 To $aRet[0]
		$aRet[$i] = DllStructGetData($struct, 1, $i)
	Next
	; ---
	Return $aRet
EndFunc

;~ declare function 	MySrv_PeersIterate	(mySrv as mySrv_t ptr, callback as mySrvIterateProc, user_data as any ptr) as integer
Func _MySrv_PeersIterate($pMySrv, $sFunc, $iUserData)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $fnc = DllCallbackRegister($sFunc, "int:cdecl", "ptr;int;ptr")
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_PeersIterate", "ptr", $pMySrv, "ptr", DllCallbackGetPtr($fnc), "ptr", $iUserData)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeersIterate)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	DllCallbackFree($fnc)
	; ---
	Return $ret[0]
EndFunc


;~ declare function		MySrv_PeerGetAddr			(mySrv as mySrv_t ptr, peer_id as integer, ip as zstring, ip_len as integer, port as ushort ptr) as integer
Func _MySrv_PeerGetAddr($pMySrv, $iPeerId)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $struct = DllStructCreate("char[512]")
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_PeerGetAddr", "ptr", $pMySrv, "int", $iPeerId, "ptr", DllStructGetPtr($struct), "uint", 512, "ushort*", 0)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerGetAddr)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	If $ret[0] = 0 Then Return 0
	; ---
	Local $aRet[2] = [DllStructGetData($struct, 1), $ret[5]]
	Return $aRet
EndFunc

Func _MySrv_PeerGetAddrStr($pMySrv, $iPeerId, $iWithPort)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $struct = DllStructCreate("char[512]")
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_PeerGetAddr", "ptr", $pMySrv, "int", $iPeerId, "ptr", DllStructGetPtr($struct), "uint", 512, "ushort*", 0)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerGetAddr)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	If $ret[0] = 0 Then Return ""
	; ---
	Local $sRet = DllStructGetData($struct, 1)
	If $iWithPort Then
		If StringInStr($sRet, ":") Then $sRet = "[" & $sRet & "]"
		$sRet &= ":" & $ret[5]
	EndIf
	Return $sRet
EndFunc

;~ declare function 	MySrv_PeerSetBuffLen		(mySrv as mySrv_t ptr, peer_id as integer, buff_len as uinteger) as integer
Func _MySrv_PeerSetBuffLen($pMySrv, $iPeerId, $iBuffLen)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_PeerSetBuffLen", "ptr", $pMySrv, "int", $iPeerId, "uint", $iBuffLen)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerSetBuffLen)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_PeerGetBuffLen		(mySrv as mySrv_t ptr, peer_id as integer) as uinteger
Func _MySrv_PeerGetBuffLen($pMySrv, $iPeerId)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "uint:cdecl", "MySrv_PeerGetBuffLen", "ptr", $pMySrv, "int", $iPeerId)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerGetBuffLen)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare sub 			MySrv_PeerSetKeepAlive		(mySrv as mySrv_t ptr, peer_id as integer, timeout as uinteger, interval as uinteger)
Func _MySrv_PeerSetKeepAlive($pMySrv, $iPeerId, $iTimeOut, $iInterval)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MySrv_PeerSetKeepAlive", "ptr", $pMySrv, "int", $iPeerId, "uint", $iTimeOut, "uint", $iInterval)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerSetKeepAlive)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc

;~ declare sub 			MySrv_PeerGetKeepAlive		(mySrv as mySrv_t ptr, peer_id as integer, timeout as uinteger ptr, interval as uinteger ptr)
Func _MySrv_PeerGetKeepAlive($pMySrv, $iPeerId)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "none:cdecl", "MySrv_PeerGetKeepAlive", "ptr", $pMySrv, "int", $iPeerId, "uint*", 0, "uint*", 0)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerGetKeepAlive)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Local $aRet[2] = [$ret[3], $ret[4]]
	Return $aRet
EndFunc

;~ declare function		MySrv_PeerGetSocket		(muSrv as mySrv_t ptr, peer_id as integer) as integer
Func _MySrv_PeerGetSocket($pMySrv, $iPeerId)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_PeerGetSocket", "ptr", $pMySrv, "int", $iPeerId)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerGetSocket)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_PeerSetUserData		(mySrv as mySrv_t ptr, peer_id as integer, user_data as any ptr) as integer
Func _MySrv_PeerSetUserData($pMySrv, $iPeerId, $iUserData)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MySrv_PeerSetUserData", "ptr", $pMySrv, "int", $iPeerId, "ptr", $iUserData)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerSetUserData)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MySrv_PeerGetUserData		(mySrv as mySrv_t ptr, peer_id as integer) as any ptr
Func _MySrv_PeerGetUserData($pMySrv, $iPeerId)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "ptr:cdecl", "MySrv_PeerGetUserData", "ptr", $pMySrv, "int", $iPeerId)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MySrv_PeerGetUserData)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

; ===============================================================================================================================

;~ declare function 	MyCln_Create		(host as zstring, port as ushort, protocol as protocol_e) as myCln_t ptr
Func _MyCln_Create($sHost, $iPort, $iProtocol = $MYSOCK_PROT_AUTO)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "ptr:cdecl", "MyCln_Create", "str", $sHost, "ushort", $iPort, "int", $iProtocol)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_Create)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MyCln_Destroy		(myCln as myCln_t ptr) as integer
Func _MyCln_Destroy($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MyCln_Destroy", "ptr", $pMyCln)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_Destroy)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MyCln_Connect		(myCln as myCln_t ptr, timeout as uinteger) as integer
Func _MyCln_Connect($pMyCln, $iTimeOut)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MyCln_Connect", "ptr", $pMyCln, "uint", $iTimeOut)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_Connect)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MyCln_Close			(myCln as myCln_t ptr) as integer
Func _MyCln_Close($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MyCln_Close", "ptr", $pMyCln)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_Close)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MyCln_IsConnected	(myCln as myCln_t ptr) as integer
Func _MyCln_IsConnected($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MyCln_IsConnected", "ptr", $pMyCln)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_IsConnected)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc


;~ declare sub 			MyCln_SetProtocol		(myCln as myCln_t ptr, protocol as protocol_e)
Func _MyCln_SetProtocol($pMyCln, $iProtocol = $MYSOCK_PROT_AUTO)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MyCln_SetProtocol", "ptr", $pMyCln, "int", $iProtocol)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_SetProtocol)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc

;~ declare function		MyCln_GetProtocol		(myCln as myCln_t ptr) as integer
Func _MyCln_GetProtocol($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MyCln_GetProtocol", "ptr", $pMyCln)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_GetProtocol)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare sub 			MyCln_SetHost			(myCln as myCln_t ptr, host as zstring, port as ushort)
Func _MyCln_SetHost($pMyCln, $sHost, $iPort)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MyCln_SetHost", "ptr", $pMyCln, "str", $sHost, "ushort", $iPort)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_SetHost)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc

;~ declare sub 			MyCln_GetHost			(myCln as myCln_t ptr, host as zstring, host_len as uinteger, port as ushort ptr)
Func _MyCln_GetHost($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $struct = DllStructCreate("char[512]")
	; ---
	Local $ret = DllCall($__gMySock_hDll, "none:cdecl", "MyCln_GetHost", "ptr", $pMyCln, "ptr", DllStructGetPtr($struct), "uint", 512, "ushort*", 0)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_GetHost)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Local $aRet[2] = [DllStructGetData($struct, 1), $ret[4]]
	Return $aRet
EndFunc

Func _MyCln_GetHostStr($pMyCln, $iWithPort)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $struct = DllStructCreate("char[512]")
	; ---
	Local $ret = DllCall($__gMySock_hDll, "none:cdecl", "MyCln_GetHost", "ptr", $pMyCln, "ptr", DllStructGetPtr($struct), "uint", 512, "ushort*", 0)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_GetHost)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Local $sRet = DllStructGetData($struct, 1)
	If $iWithPort Then
		If StringInStr($sRet, ":") Then $sRet = "[" & $sRet & "]"
		$sRet &= ":" & $ret[4]
	EndIf
	Return $sRet
EndFunc

;~ declare sub 			MyCln_GetSrvIp			(myCln as myCln_t ptr, ip as zstring, ip_len as uinteger)
Func _MyCln_GetSrvIp($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $struct = DllStructCreate("char[512]")
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MyCln_GetSrvIp", "ptr", $pMyCln, "ptr", DllStructGetPtr($struct, 1), "uint", 512)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_GetSrvIp)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return DllStructGetData($struct, 1)
EndFunc


;~ declare sub 			MyCln_SetCallbacks	(myCln as myCln_t ptr, onDisconnect as myClnOnDisconnectProc, onRecv as myClnOnRecvProc)
Func _MyCln_SetCallbacks($pMyCln, $sOnDisconnect, $sOnRecv)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MyCln_SetCallbacks", "ptr", $pMyCln, _
		"ptr", __MySock_SetCallback($sOnDisconnect, $MYSOCK_CB_CLN_ONDISCONNECT), _
		"ptr", __MySock_SetCallback($sOnRecv, $MYSOCK_CB_CLN_ONRECV) _
	)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_SetCallbacks)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc

;~ declare sub 			MyCln_Process		(myCln as myCln_t ptr)
Func _MyCln_Process($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MyCln_Process", "ptr", $pMyCln)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_Process)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc


;~ declare function 	MyCln_Send	(myCln as myCln_t ptr, data_ as byte ptr, data_len as uinteger) as integer
Func _MyCln_Send($pMyCln, $bData)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $len = BinaryLen($bData)
	Local $struct = DllStructCreate("byte[" & $len & "]")
	DllStructSetData($struct, 1, $bData)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MyCln_Send", "ptr", $pMyCln, "ptr", DllStructGetPtr($struct), "uint", $len)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_Send)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc


;~ declare function		MyCln_SetBuffLen	(myCln as myCln_t ptr, buff_len as uinteger) as integer
Func _MyCln_SetBuffLen($pMyCln, $iBuffLen)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MyCln_SetBuffLen", "ptr", $pMyCln, "uint", $iBuffLen)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_SetBuffLen)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function		MyCln_GetBuffLen	(myCln as myCln_t ptr) as uinteger
Func _MyCln_GetBuffLen($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "uint:cdecl", "MyCln_GetBuffLen", "ptr", $pMyCln)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_GetBuffLen)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare function 	MyCln_SetKeepAlive 	(myCln as myCln_t ptr, timeout as uinteger, interval as uinteger) as integer
Func _MyCln_SetKeepAlive($pMyCln, $iTimeOut, $iInterval)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MyCln_SetKeepAlive", "ptr", $pMyCln, "uint", $iTimeOut, "uint", $iInterval)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_SetKeepAlive)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare sub 			MyCln_GetKeepAlive 	(myCln as myCln_t ptr, timeout as uinteger ptr, interval as uinteger ptr)
Func _MyCln_GetKeepAlive($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "none:cdecl", "MyCln_GetKeepAlive", "ptr", $pMyCln, "uint*", 0, "uint*", 0)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_GetKeepAlive)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Local $aRet[2] = [$ret[2], $ret[3]]
	Return $aRet
EndFunc

;~ declare function		MyCln_GetSocket		(myCln as myCln_t ptr) as integer
Func _MyCln_GetSocket($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "int:cdecl", "MyCln_GetSocket", "ptr", $pMyCln)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_GetSocket)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

;~ declare sub 			MyCln_SetUserData 	(myCln as myCln_t ptr, user_data as any ptr)
Func _MyCln_SetUserData($pMyCln, $iUserData)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	DllCall($__gMySock_hDll, "none:cdecl", "MyCln_SetUserData", "ptr", $pMyCln, "ptr", $iUserData)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_SetUserData)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return 1
EndFunc

;~ declare function 	MyCln_GetUserData 	(myCln as myCln_t ptr) as any ptr
Func _MyCln_GetUserData($pMyCln)
	If $__gMySock_hDll = -1 Then Return SetError(-1, 0, 0)
	; ---
	Local $ret = DllCall($__gMySock_hDll, "ptr:cdecl", "MyCln_GetUserData", "ptr", $pMyCln)
	If @error Then
		Local $err = @error
		If Not @Compiled Then ConsoleWrite("! DllCall error " & $err & " (MyCln_GetUserData)" & @CRLF)
		Return SetError($err, 0, 0)
	EndIf
	; ---
	Return $ret[0]
EndFunc

; #INTERNAL_USE_ONLY# ===========================================================================================================

Func __MySock_SetCallback($sFunc, $iCbId)
	DllCallbackFree($__gMySock_aCallbacks[$iCbId][0])
	$__gMySock_aCallbacks[$iCbId][0] = 0
	; ---
	If $sFunc Then
		Switch $iCbId
			Case $MYSOCK_CB_SRV_ONRECV
				$__gMySock_sSrvOnRecv = $sFunc
				$sFunc = "__MySock_SpecCb_SrvOnRecv"
			Case $MYSOCK_CB_CLN_ONRECV
				$__gMySock_sClnOnRecv = $sFunc
				$sFunc = "__MySock_SpecCb_ClnOnRecv"
		EndSwitch
		; ---
		$__gMySock_aCallbacks[$iCbId][0] = DllCallbackRegister($sFunc, $__gMySock_aCallbacks[$iCbId][1], $__gMySock_aCallbacks[$iCbId][2])
	Else
		Switch $iCbId
			Case $MYSOCK_CB_SRV_ONRECV
				$__gMySock_sSrvOnRecv = ""
			Case $MYSOCK_CB_CLN_ONRECV
				$__gMySock_sClnOnRecv = ""
		EndSwitch
	EndIf
	; ---
	Return DllCallbackGetPtr($__gMySock_aCallbacks[$iCbId][0])
EndFunc

Func __MySock_FreeCallbacks()
	For $i = 0 To UBound($__gMySock_aCallbacks) - 1
		DllCallbackFree($__gMySock_aCallbacks[$i][0])
	Next
EndFunc

Func __MySock_SpecCb_SrvOnRecv($pMySrv, $iPeerId, $pData, $iDataLen)
	Local $struct = DllStructCreate("byte[" & $iDataLen & "]", $pData)
	Call($__gMySock_sSrvOnRecv, $pMySrv, $iPeerId, DllStructGetData($struct, 1))
EndFunc

Func __MySock_SpecCb_ClnOnRecv($pMyCln, $pData, $iDataLen)
	Local $struct = DllStructCreate("byte[" & $iDataLen & "]", $pData)
	Call($__gMySock_sClnOnRecv, $pMyCln, DllStructGetData($struct, 1))
EndFunc
