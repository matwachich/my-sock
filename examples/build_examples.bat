@echo off
cls

:start
echo (a) Build all
echo (q) Exit
echo (1) Build simple_srv.bas
echo (2) Build simple_cln.bas
echo (3) Build tcp_listen.bas
echo (4) Build tcp_connect.bas
echo (5) Build tcp_http_get.bas
set /p choice=Choose an option: 

rem ============================================================================

if %choice%==a goto build_all
if %choice%==q goto end
if %choice%==1 goto simple_srv
if %choice%==2 goto simple_cln
if %choice%==3 goto tcp_listen
if %choice%==4 goto tcp_connect
if %choice%==5 goto tcp_http_get
goto error

rem ============================================================================

:error
echo Invalid choice!
pause
cls
goto start

rem ============================================================================

:build_all
fbc -i ..\ -p ..\bin\lib\ -gen gas simple_srv.bas
fbc -i ..\ -p ..\bin\lib\ -gen gas simple_cln.bas
fbc -i ..\ -p ..\bin\lib\ -gen gas tcp_listen.bas
fbc -i ..\ -p ..\bin\lib\ -gen gas tcp_connect.bas
fbc -i ..\ -p ..\bin\lib\ -gen gas tcp_http_get.bas
echo All done!
pause
cls
goto start

:simple_srv
fbc -i ..\ -p ..\bin\lib\ -gen gas simple_srv.bas
pause
cls
goto start

:simple_cln
fbc -i ..\ -p ..\bin\lib\ -gen gas simple_cln.bas
pause
cls
goto start

:tcp_listen
fbc -i ..\ -p ..\bin\lib\ -gen gas tcp_listen.bas
pause
cls
goto start

:tcp_connect
fbc -i ..\ -p ..\bin\lib\ -gen gas tcp_connect.bas
pause
cls
goto start

:tcp_http_get
fbc -i ..\ -p ..\bin\lib\ -gen gas tcp_http_get.bas
pause
cls
goto start

rem ============================================================================

:end