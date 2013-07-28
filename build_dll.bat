@echo off
md bin
md bin\dll
fbc -gen gas -dll -export -x bin\dll\mysock.dll main.bas myserver.bas myclient.bas mytcp.bas internals.bas
copy /Y /V bin\dll\mysock.dll test\mysock.dll
copy /Y /V bin\dll\mysock.dll au3\mysock.dll
copy /Y /V bin\dll\libmysock.dll.a test\libmysock.dll.a
pause