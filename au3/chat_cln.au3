#NoTrayIcon
#include <EditConstants.au3>
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>

#include "mysock.au3"

_MySock_Startup()
OnAutoItExitRegister("_MySock_Shutdown")

; We need a nickname
Do
	$sName = InputBox("Chat Client", "Enter you name", "", "", 240, 140)
	If @error Then Exit
Until $sName

; ===============================================================================================================================

Global $sWinTitle = "Chat Client - " & $sName

#Region ### START Koda GUI section ###
Global $hGUI = GUICreate($sWinTitle & " (disconnected)", 442, 262)
Global $Input = GUICtrlCreateInput("", 0, 240, 442, 21)
Global $Edit = GUICtrlCreateEdit("", 0, 0, 442, 233, BitOR($ES_AUTOVSCROLL,$ES_READONLY,$ES_WANTRETURN,$WS_VSCROLL))
GUISetState(@SW_SHOW)
#EndRegion ### END Koda GUI section ###

; Create a TCP Client and set its callbacks
Global $pClient = _MyCln_Create("localhost", 41526, $MYSOCK_PROT_IPV4)
_MyCln_SetCallbacks($pClient, "_onDisconnect", "_onPacketRecv", "", "")

; A function to connect to the server
Global $iConnectTimer
Func _Connect()
	If _MyCln_Connect($pClient, 5) Then
		; If connected succesfully, send the nickname, and change the window title
		_MyCln_Send($pClient, StringToBinary("name" & Chr(3) & $sName))
		WinSetTitle($hGUI, "", $sWinTitle & " (connected)")
	EndIf
	$iConnectTimer = TimerInit()
EndFunc

While 1
	Switch GUIGetMsg()
		Case $GUI_EVENT_CLOSE
			ExitLoop
		Case $Input
			$sRead = GUICtrlRead($Input)
			If $sRead And _MyCln_IsConnected($pClient) Then
				; Send a message
				_MyCln_Send($pClient, StringToBinary("msg" & Chr(3) & $sRead))
				GUICtrlSetData($Input, "")
			EndIf
	EndSwitch
	; ---
	; If not connected, then retry every 5 seconds
	If Not _MyCln_IsConnected($pClient) And TimerDiff($iConnectTimer) >= 5000 Then _Connect()
	_MyCln_Process($pClient)
WEnd

_MyCln_Destroy($pClient)

; ===============================================================================================================================

; Change window title on disconnection
Func _onDisconnect($pClient, $bPartialData, $iExceptedLen)
	WinSetTitle($hGUI, "", $sWinTitle & " (disconnected)")
EndFunc

Func _onPacketRecv($pClient, $bData)
	$bData = BinaryToString($bData)
;~ 	ConsoleWrite($bData & @CRLF)
	$bData = StringSplit($bData, Chr(3))
	If $bData[0] <> 2 Then Return ; ConsoleWrite("! Server sent a packet that I can't understand :(" & @CRLF)
	; ---
	Switch $bData[1]
		Case "msg"
			Local $msg = StringSplit($bData[2], Chr(31))
			If $msg[0] <> 2 Then Return
			; ---
			GUICtrlSetData($Edit, GUICtrlRead($Edit) & $msg[1] & " - " & $msg[2] & @CRLF)
		Case Else
;~ 			ConsoleWrite("! Server sent a packet that I can't understand :(" & @CRLF)
	EndSwitch
EndFunc
