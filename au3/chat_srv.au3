#NoTrayIcon
#include <EditConstants.au3>
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>

#include "mysock.au3"

Const $tagPEERDATA = "char[128]"

_MySock_Startup()
OnAutoItExitRegister("_MySock_Shutdown")

; =============================================================================================================================

; Create a TCP Server and set its callbacks
Global $pServer = _MySrv_Create(10, $MYSOCK_PROT_IPV4)
_MySrv_SetCallbacks($pServer, "_onConnect", "_onDisconnect", "_onPacketRecv", "", "")

; Start the server
If Not _MySrv_Start($pServer, 41526) Then
	_MySrv_Destroy($pServer)
	Exit 0 * MsgBox(16, "Server", "Unable to start server (check port)")
EndIf

#Region ### START Koda GUI section ###
Global $hGUI = GUICreate("Chat Server", 338, 162)
Global $Edit = GUICtrlCreateEdit("", 0, 0, 338, 162, BitOR($ES_READONLY, $WS_VSCROLL, $ES_AUTOVSCROLL, $ES_WANTRETURN))
GUISetState(@SW_SHOW)
#EndRegion ### END Koda GUI section ###

While GUIGetMsg() <> $GUI_EVENT_CLOSE
	_MySrv_Process($pServer)
	Sleep(50)
WEnd

_MySrv_Destroy($pServer)

; ===============================================================================================================================

Func _onConnect($pSrv, $iPeer)
	_out("New connection from: " & _MySrv_PeerGetAddrStr($pSrv, $iPeer, 1))
	; ---
	; Attaching dynamic allocated structure to the new peer
	Local $struct = DllStructCreate($tagPEERDATA, malloc(128)) ; 128 bytes
	DllStructSetData($struct, 1, "")
	_MySrv_PeerSetUserData($pSrv, $iPeer, DllStructGetPtr($struct))
EndFunc

Func _onDisconnect($pSrv, $iPeer, $bPartialData, $iExceptedLen)
	_out("Lost connection from: " & _MySrv_PeerGetAddrStr($pSrv, $iPeer, 1) & " (identified as " & _peerData($pSrv, $iPeer, 1) & ")")
	; ---
	; Notify lost connection
	_MySrv_Broadcast($pSrv, StringToBinary("msg" & Chr(3) & "[SERVER]" & Chr(31) & "Goodbye " & _peerData($pSrv, $iPeer, 1) & "!"))
	; ---
	; Free the allocated structure
	free(_MySrv_PeerGetUserData($pSrv, $iPeer))
EndFunc

Func _onPacketRecv($pSrv, $iPeer, $bData)
	$bData = BinaryToString($bData)
	ConsoleWrite($bData & @CRLF)
	$bData = StringSplit($bData, Chr(3))
	If $bData[0] <> 2 Then Return ; ConsoleWrite("! Server sent a packet that I can't understand :(" & @CRLF)
	; ---
	Switch $bData[1]
		Case "name"
			_peerData($pSrv, $iPeer, 1, $bData[2])
			; ---
			; Notify new connection
			_MySrv_Broadcast($pSrv, StringToBinary("msg" & Chr(3) & "[SERVER]" & Chr(31) & "Welcome " & $bData[2] & "!"))
			; ---
			_out(_MySrv_PeerGetAddrStr($pSrv, $iPeer, 1) & " identified as " & $bData[2])
		Case "msg"
			_MySrv_Broadcast($pSrv, StringToBinary("msg" & Chr(3) & _peerData($pSrv, $iPeer, 1) & Chr(31) & $bData[2]))
		Case Else
;~ 			ConsoleWrite("! Client sent a packet that I can't understand :(" & @CRLF)
	EndSwitch
EndFunc

; ===============================================================================================================================

; Just write some data in the Server's window
Func _out($sData)
	GUICtrlSetData($Edit, GUICtrlRead($Edit) & $sData & @CRLF)
EndFunc

; Get/Set peer attached data
Func _peerData($pSrv, $iPeer, $iData, $vValue = Default)
	Local $struct = DllStructCreate($tagPEERDATA, _MySrv_PeerGetUserData($pSrv, $iPeer))
	If $vValue <> Default Then DllStructSetData($struct, $iData, $vValue)
	Return DllStructGetData($struct, $iData)
EndFunc

Func malloc($iSize)
	Local $ret = DllCall("msvcrt.dll", "ptr:cdecl", "malloc", "uint", $iSize)
	Return $ret[0]
EndFunc

Func free($pMem)
	DllCall("msvcrt.dll", "none:cdecl", "free", "ptr", $pMem)
EndFunc
