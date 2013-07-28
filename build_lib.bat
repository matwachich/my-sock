@echo off
md bin
md bin\lib
fbc -gen gas -lib -x bin\lib\libmysock.a main.bas myserver.bas myclient.bas mytcp.bas internals.bas
copy /Y /V bin\lib\libmysock.a test\libmysock.a
pause