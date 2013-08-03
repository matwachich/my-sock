#NoTrayIcon
#include "mysock.au3"

_MySock_Startup()
; ---

$pSrv = _MySrv_Create(100, $MYSOCK_PROT_IPV4)
_MySrv_SetCallbacks($pSrv, "_OnConnect", "_OnDisconnect", "_OnRecv", "_OnReceiving", "")
_MySrv_Start($pSrv, 8080)

ConsoleWrite("Server listening: " & _MySrv_GetAddrStr($pSrv, 1) & @CRLF)

Global $iRun = 1
While $iRun
	_MySrv_Process($pSrv)
	Sleep(100)
WEnd

_MySrv_Stop($pSrv)
_MySrv_Destroy($pSrv)

; ---
_MySock_Shutdown()

; ===============================================================================================================================

Func _OnConnect($pSrv, $iPeerId)
	ConsoleWrite("+ Peer: " & $iPeerId & " [" & _MySrv_PeerGetAddrStr($pSrv, $iPeerId, 1) & "]" & @CRLF)
EndFunc

Func _OnDisconnect($pSrv, $iPeerId)
	ConsoleWrite("! Peer: " & $iPeerId & " [" & _MySrv_PeerGetAddrStr($pSrv, $iPeerId, 1) & "]" & @CRLF)
	$iRun = 0
EndFunc

Func _OnRecv($pSrv, $iPeerId, $bData)
	$bData = BinaryToString($bData)
	ConsoleWrite("- Recv: " & $iPeerId & " [" & _MySrv_PeerGetAddrStr($pSrv, $iPeerId, 1) & "]" & @CRLF & $bData & @CRLF)
	; ---
	Switch $bData
		Case "Salut!"
			_MySrv_PeerSend($pSrv, $iPeerId, StringToBinary("Salut!"))
		Case "Bye!"
			_MySrv_PeerSend($pSrv, $iPeerId, StringToBinary("Bye!"))
	EndSwitch
EndFunc

Func _OnReceiving($pSrv, $iPeerId, $iReceived, $iTotal)
	ConsoleWrite("Receiving ...	[" & $iPeerId & "] " & $iReceived & " / " & $iTotal & @CRLF)
EndFunc
