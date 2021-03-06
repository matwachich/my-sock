#NoTrayIcon
#include "mysock.au3"

_MySock_Startup()

$pCln = _MyCln_Create("localhost", 8080, $MYSOCK_PROT_IPV4)
_MyCln_SetCallbacks($pCln, "_OnDisconnect", "_OnRecv", "_OnReceiving", "")

If Not _MyCln_Connect($pCln, 5) Then Exit -1
ConsoleWrite("+ Connected to: " & _MyCln_GetHostStr($pCln, 1) & " -> " & _MyCln_GetSrvIp($pCln) & @CRLF)

_MyCln_Send($pCln, StringToBinary("Hi! Ceci est un long message, pour voir un peut est-ce que le syst�me est capable de s�parer les diff�rents messages (packets) envoy�s."))
_MyCln_Send($pCln, StringToBinary("Salut!"))

Global $iRun = 1
While $iRun
	_MyCln_Process($pCln)
	Sleep(100)
WEnd

_MyCln_Destroy($pCln)
_MySock_Shutdown()

; ===============================================================================================================================

Func _OnDisconnect($pCln, $bPartialData, $iExceptedLen)
	ConsoleWrite("! Disconnected" & @CRLF)
EndFunc

Func _OnRecv($pCln, $bData)
	$bData = BinaryToString($bData)
	ConsoleWrite("- Recv: " & $bData & @CRLF)
	; ---
	Switch $bData
		Case "Salut!"
			_MyCln_Send($pCln, StringToBinary("Bye!"))
		Case "Bye!"
			$iRun = 0
	EndSwitch
EndFunc

Func _OnReceiving($pCln, $iReceived, $iTotal)
	ConsoleWrite("Receiving ...	" & $iReceived & " / " & $iTotal & @CRLF)
EndFunc
