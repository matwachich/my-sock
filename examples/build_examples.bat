@echo off
fbc -i ..\ -p ..\bin\lib\ -gen gas simple_srv.bas
fbc -i ..\ -p ..\bin\lib\ -gen gas simple_cln.bas
pause